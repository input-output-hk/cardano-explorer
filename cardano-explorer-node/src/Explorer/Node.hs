{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}

module Explorer.Node
  ( ExplorerNodeParams (..)
  , GenesisFile (..)
  , NodeLayer (..)
  , SocketPath (..)
  , initializeAllFeatures
  ) where

import           Control.Exception (throw)
import           Control.Monad.Class.MonadST (MonadST)
import           Control.Monad.Class.MonadSTM.Strict (MonadSTM, StrictTMVar,
                    atomically, newEmptyTMVarM, readTMVar)
import           Control.Monad.Class.MonadTimer (MonadTimer)

import           Cardano.BM.Data.Tracer (ToLogObject (..), nullTracer)
import           Cardano.BM.Trace (Trace, appendName, logInfo)

import qualified Cardano.Chain.Genesis as Genesis
import qualified Cardano.Chain.Update as Update

import           Cardano.Config.CommonCLI (CommonCLI (..))
import qualified Cardano.Config.CommonCLI as Config
import           Cardano.Config.Logging (LoggingLayer, LoggingCLIArguments,
                    createLoggingFeature, llAppendName, llBasicTrace)
import qualified Cardano.Config.Partial as Config
import qualified Cardano.Config.Presets as Config
import           Cardano.Config.Types (CardanoConfiguration, CardanoEnvironment (..),
                    RequireNetworkMagic (..),
                    coRequiresNetworkMagic, ccCore)

import           Cardano.Crypto (RequiresNetworkMagic (..), decodeAbstractHash)
import           Cardano.Crypto.Hashing (AbstractHash (..))

import           Cardano.Prelude hiding (atomically, option, (%), Nat)
import           Cardano.Shell.Lib (GeneralException (ConfigurationError))
import           Cardano.Shell.Types (CardanoFeature (..),
                    CardanoFeatureInit (..), featureCleanup, featureInit,
                    featureShutdown, featureStart, featureType)

import qualified Codec.Serialise as Serialise
import           Crypto.Hash (digestFromByteString)

import qualified Data.ByteString.Lazy as BSL
import           Data.Functor.Contravariant (contramap)
import           Data.Reflection (give)
import           Data.Text (Text)
import qualified Data.Text as Text


import           Explorer.DB (LogFileDir (..), MigrationDir)
import qualified Explorer.DB as DB
import           Explorer.Node.Insert
import           Explorer.Node.Rollback

import           Network.Socket (AddrInfo (..), Family (..), SockAddr (..), SocketType (..),
                    defaultProtocol)

import           Network.TypedProtocol.Codec (Codec)
import           Network.TypedProtocol.Codec.Cbor (DeserialiseFailure)
import           Network.TypedProtocol.Driver (runPeer, runPipelinedPeer)
import           Network.TypedProtocol.Pipelined (Nat(Zero, Succ))

import           Ouroboros.Consensus.Ledger.Abstract (BlockProtocol)
import           Ouroboros.Consensus.Ledger.Byron (ByronBlockOrEBB (..), ByronHash (..), GenTx, ByronGiven)
import           Ouroboros.Consensus.Ledger.Byron.Config (ByronConfig)
import           Ouroboros.Consensus.Node.ProtocolInfo (NumCoreNodes (..),
                    pInfoConfig, protocolInfo)
import           Ouroboros.Consensus.Node.Run.Abstract (RunNode, nodeDecodeBlock, nodeDecodeGenTx,
                    nodeDecodeHeaderHash, nodeEncodeBlock, nodeEncodeGenTx, nodeEncodeHeaderHash)
import           Ouroboros.Consensus.NodeId (CoreNodeId (..))
import           Ouroboros.Consensus.Protocol (NodeConfig, Protocol (..))
import           Ouroboros.Network.Block (Point (..), SlotNo (..), Tip (tipBlockNo),
                    decodePoint, encodePoint, genesisPoint, genesisBlockNo, blockNo,
                    BlockNo(unBlockNo, BlockNo),
                    encodeTip, decodeTip)
import           Ouroboros.Network.Mux (AppType (..), OuroborosApplication (..))
import           Ouroboros.Network.NodeToClient (NodeToClientProtocols (..),
                    NodeToClientVersion (..), NodeToClientVersionData (..),
                    connectTo, networkMagic, nodeToClientCodecCBORTerm)
import qualified Ouroboros.Network.Point as Point
import           Ouroboros.Network.Protocol.ChainSync.ClientPipelined (ChainSyncClientPipelined (..),
                    ClientPipelinedStIdle (..), ClientPipelinedStIntersect (..), ClientStNext (..),
                    chainSyncClientPeerPipelined, recvMsgIntersectFound, recvMsgIntersectNotFound,
                    recvMsgRollBackward, recvMsgRollForward)
import           Ouroboros.Network.Protocol.ChainSync.PipelineDecision (pipelineDecisionLowHighMark, PipelineDecision(Collect, Request, Pipeline, CollectOrPipeline), runPipelineDecision, MkPipelineDecision)
import           Ouroboros.Network.Protocol.ChainSync.Codec (codecChainSync)
import           Ouroboros.Network.Protocol.ChainSync.Type (ChainSync)

import           Ouroboros.Network.Protocol.Handshake.Version (DictVersion (..), Versions,
                    simpleSingletonVersions)
import           Ouroboros.Network.Protocol.LocalTxSubmission.Client (LocalTxSubmissionClient (..),
                    LocalTxClientStIdle (..), localTxSubmissionClientPeer)
import           Ouroboros.Network.Protocol.LocalTxSubmission.Codec (codecLocalTxSubmission)
import           Ouroboros.Network.Protocol.LocalTxSubmission.Type (LocalTxSubmission)

import           Prelude (String, id)

import qualified System.Metrics.Prometheus.Metric.Gauge as Gauge
import           System.Metrics.Prometheus.Http.Scrape (serveHttpTextMetricsT)
import           System.Metrics.Prometheus.Concurrent.RegistryT

import           Control.Concurrent.STM.TBQueue (newTBQueueIO, TBQueue, writeTBQueue, readTBQueue, lengthTBQueue, flushTBQueue)
import           Control.Concurrent.STM.TVar (TVar, readTVar, newTVarIO, writeTVar)

data Peer = Peer SockAddr SockAddr deriving Show

-- | The product type of all command line arguments
data ExplorerNodeParams = ExplorerNodeParams
  { enpLogging :: !LoggingCLIArguments
  , enpGenesisHash :: !Text
  , enpGenesisFile :: !GenesisFile
  , enpSocketPath :: !SocketPath
  , enpMigrationDir :: !MigrationDir
  , enpCommonCLIAdvanced :: !Config.CommonCLIAdvanced
  }

newtype GenesisFile = GenesisFile
  { unGenesisFile :: FilePath
  }

newtype SocketPath = SocketPath
  { unSocketPath :: FilePath
  }

newtype NodeLayer = NodeLayer
  { nlRunNode :: forall m. MonadIO m => m ()
  }

type NodeCardanoFeature
  = CardanoFeatureInit CardanoEnvironment LoggingLayer CardanoConfiguration ExplorerNodeParams NodeLayer

data Metrics = Metrics
  { mNodeHeight :: Gauge.Gauge
  , mQueuePre :: Gauge.Gauge
  , mQueuePost :: Gauge.Gauge
  , mQueuePostWrite :: Gauge.Gauge
  }

initializeAllFeatures :: ExplorerNodeParams -> IO ([CardanoFeature], NodeLayer)
initializeAllFeatures enp = do
  DB.runMigrations id True (enpMigrationDir enp) (LogFileDir "/tmp")
  let fcc = Config.finaliseCardanoConfiguration $ Config.mergeConfiguration Config.mainnetConfiguration commonCli (enpCommonCLIAdvanced enp)
  finalConfig <- case fcc of
                  Left err -> throwIO err
                  --TODO: if we're using exceptions for this, then we should use a local
                  -- excption type, local to this app, that enumerates all the ones we
                  -- are reporting, and has proper formatting of the result.
                  -- It would also require catching at the top level and printing.
                  Right x  -> pure x

  (loggingLayer, loggingFeature) <- createLoggingFeature NoEnvironment finalConfig (enpLogging enp)
  (nodeLayer   , nodeFeature)    <- createNodeFeature loggingLayer enp finalConfig

  pure ([ loggingFeature, nodeFeature ], nodeLayer)

-- This is a bit of a pain in the neck but is needed for using cardano-cli.
commonCli ::CommonCLI
commonCli =
  CommonCLI
    { Config.cliSocketDir = Last Nothing
    , Config.cliGenesisFile = Last Nothing
    , Config.cliGenesisHash = Last Nothing
    , Config.cliStaticKeySigningKeyFile = Last Nothing
    , Config.cliStaticKeyDlgCertFile = Last Nothing
    , Config.cliDBPath = Last Nothing
    }

createNodeFeature :: LoggingLayer -> ExplorerNodeParams -> CardanoConfiguration -> IO (NodeLayer, CardanoFeature)
createNodeFeature loggingLayer enp cardanoConfiguration = do
  -- we parse any additional configuration if there is any
  -- We don't know where the user wants to fetch the additional configuration from, it could be from
  -- the filesystem, so we give him the most flexible/powerful context, @IO@.

  -- we construct the layer
  nodeLayer <- featureInit nodeCardanoFeatureInit NoEnvironment loggingLayer cardanoConfiguration enp

  -- Return both
  pure (nodeLayer, nodeCardanoFeature nodeCardanoFeatureInit nodeLayer)

nodeCardanoFeatureInit :: NodeCardanoFeature
nodeCardanoFeatureInit =
    CardanoFeatureInit
      { featureType    = "NodeFeature"
      , featureInit    = featureStart'
      , featureCleanup = featureCleanup'
      }
  where
    featureStart' :: CardanoEnvironment -> LoggingLayer -> CardanoConfiguration -> ExplorerNodeParams -> IO NodeLayer
    featureStart' _ loggingLayer cc enp =
        pure $ NodeLayer { nlRunNode = liftIO $ runClient enp (mkTracer loggingLayer) cc }

    featureCleanup' :: NodeLayer -> IO ()
    featureCleanup' _ = pure ()

    mkTracer :: LoggingLayer -> Trace IO Text
    mkTracer loggingLayer = llAppendName loggingLayer "explorer-db-node" (llBasicTrace loggingLayer)


nodeCardanoFeature :: NodeCardanoFeature -> NodeLayer -> CardanoFeature
nodeCardanoFeature nodeCardanoFeature' nodeLayer =
  CardanoFeature
    { featureName       = featureType nodeCardanoFeature'
    , featureStart      = pure ()
    , featureShutdown   = liftIO $ (featureCleanup nodeCardanoFeature') nodeLayer
    }

runClient :: ExplorerNodeParams -> Trace IO Text -> CardanoConfiguration -> IO ()
runClient enp trce cc = do
    gc <- readGenesisConfig enp cc

    -- If the DB is empty it will be inserted, otherwise it will be validated (to make
    -- sure we are on the right chain).
    insertValidateGenesisDistribution trce gc

    give (Genesis.configEpochSlots gc)
          $ give (Genesis.gdProtocolMagicId $ Genesis.configGenesisData gc)
          $ runExplorerNodeClient (mkProtocolId gc) trce (unSocketPath $ enpSocketPath enp)


mkProtocolId :: Genesis.Config -> Protocol (ByronBlockOrEBB ByronConfig)
mkProtocolId gc =
  ProtocolRealPBFT gc Nothing
    (Update.ProtocolVersion 0 2 0)
    (Update.SoftwareVersion (Update.ApplicationName "cardano-sl") 1)
    Nothing


data GenesisConfigurationError = GenesisConfigurationError Genesis.ConfigurationError
  deriving (Show, Typeable)

instance Exception GenesisConfigurationError

readGenesisConfig :: ExplorerNodeParams -> CardanoConfiguration -> IO Genesis.Config
readGenesisConfig enp cc = do
    genHash <- either (throw . ConfigurationError) pure $ decodeAbstractHash (enpGenesisHash enp)
    convert =<< runExceptT (Genesis.mkConfigFromFile (convertRNM . coRequiresNetworkMagic $ ccCore cc)
                            (unGenesisFile $ enpGenesisFile enp) genHash)
  where
    convert :: Either Genesis.ConfigurationError Genesis.Config -> IO Genesis.Config
    convert =
      \case
        Left err -> throw (GenesisConfigurationError err)   -- TODO: no no no!
        Right x -> pure x


convertRNM :: RequireNetworkMagic -> RequiresNetworkMagic
convertRNM =
  \case
    NoRequireNetworkMagic -> RequiresNoMagic
    RequireNetworkMagic -> RequiresMagic

runExplorerNodeClient
    :: forall blk cfg.
        (RunNode blk, blk ~ ByronBlockOrEBB cfg, ByronGiven, cfg ~ ByronConfig)
    => Ouroboros.Consensus.Protocol.Protocol blk -> Trace IO Text -> FilePath -> IO ()
runExplorerNodeClient ptcl trce socketPath = do
  liftIO $ logInfo trce "Starting node client"
  let
    infoConfig = pInfoConfig $ protocolInfo (NumCoreNodes 7) (CoreNodeId 0) ptcl

    addr = localSocketAddrInfo socketPath

  logInfo trce $ "localInitiatorNetworkApplication: connecting to node via " <> Text.pack (show socketPath)
  connectTo
    -- TODO: these tracers should be configurable for debugging purposes.
    nullTracer
    nullTracer
    Peer
    (localInitiatorNetworkApplication (Proxy :: Proxy blk) trce infoConfig)
    Nothing
    addr

localSocketAddrInfo :: FilePath -> AddrInfo
localSocketAddrInfo socketPath =
  AddrInfo [] AF_UNIX Stream defaultProtocol (SockAddrUnix socketPath) Nothing


localInitiatorNetworkApplication
  :: forall blk peer cfg.
     (RunNode blk, blk ~ ByronBlockOrEBB cfg, Show peer, ByronGiven, cfg ~ ByronConfig)
  -- TODO: the need of a 'Proxy' is an evidence that blk type is not really
  -- needed here.  The wallet client should use some concrete type of block
  -- from 'cardano-chain'.  This should remove the dependency of this module
  -- from 'ouroboros-consensus'.
  => Proxy blk
  -> Trace IO Text
  -> NodeConfig (BlockProtocol blk)
  -> Versions NodeToClientVersion DictVersion
              (OuroborosApplication 'InitiatorApp peer NodeToClientProtocols
                                    IO BSL.ByteString Void Void)
localInitiatorNetworkApplication Proxy trce pInfoConfig =
    simpleSingletonVersions
      NodeToClientV_1
      (NodeToClientVersionData { networkMagic = 0 })
      (DictVersion nodeToClientCodecCBORTerm)
      initialApp
  where
    initialApp :: OuroborosApplication 'InitiatorApp peer NodeToClientProtocols IO BSL.ByteString Void Void
    initialApp =
      OuroborosInitiatorApplication $ \peer ptcl ->
        case ptcl of
          LocalTxSubmissionPtcl -> \channel -> do
            txv <- newEmptyTMVarM @_ @(GenTx blk)
            runPeer
              (contramap (Text.pack . show) . toLogObject $ appendName "explorer-db-local-tx" trce)
              localTxSubmissionCodec
              peer
              channel
              (localTxSubmissionClientPeer (txSubmissionClient @(GenTx blk) txv))

          ChainSyncWithBlocksPtcl -> \channel -> do
            liftIO $ logInfo trce "Starting chainSyncClient"
            latestPoints <- liftIO getLatestPoints
            currentTip <- liftIO getCurrentTip
            liftIO $ logDbState trce
            actionQueue <- newSingleTypeQueueIO
            (metrics, server) <- runRegistryT $ do
              metrics <- makeMetrics
              registry <- RegistryT ask
              server <- liftIO $ async $ runReaderT (unRegistryT $ serveHttpTextMetricsT 8080 []) registry
              pure (metrics, server)
            dbThread <- async $ startDbThread trce actionQueue metrics
            wut <- runPipelinedPeer
              nullTracer -- TODO
              (localChainSyncCodec @blk pInfoConfig)
              peer
              channel
              (chainSyncClientPeerPipelined (chainSyncClient trce metrics latestPoints currentTip actionQueue))
            atomically $ do
              currentState <- readTVar (stqContains actionQueue)
              check (currentState == Empty)
              writeTBQueue (stqQueue actionQueue) Finish
              writeTVar (stqContains actionQueue) Other
            wait dbThread
            cancel server
            pure wut

makeMetrics :: RegistryT IO Metrics
makeMetrics = do
  mNodeHeight <- registerGauge "remote_tip_height" mempty
  mQueuePre <- registerGauge "action_queue_length_pre" mempty
  mQueuePost <- registerGauge "action_queue_length_post" mempty
  mQueuePostWrite <- registerGauge "action_queue_length_post_write" mempty
  pure $ Metrics{mNodeHeight,mQueuePre,mQueuePost,mQueuePostWrite}

newSingleTypeQueueIO :: IO SingleTypeQueue
newSingleTypeQueueIO = SingleTypeQueue <$> newTVarIO Empty <*> newTBQueueIO 1000


logDbState :: Trace IO Text -> IO ()
logDbState trce = do
    mblk <- DB.runDbNoLogging DB.queryLatestBlock
    case mblk of
      Nothing -> logInfo trce "Explorer DB is empty"
      Just block ->
          logInfo trce $ Text.concat
                  [ "Explorer DB tip is at "
                  , Text.pack (showTip block)
                  ]
  where
    showTip :: DB.Block -> String
    showTip blk =
      case (DB.blockBlockNo blk, DB.blockSlotNo blk) of
        (Just blkNo, Just slotNo) -> "block " ++ show blkNo ++ ", slot " ++ show slotNo
        (Just blkNo, Nothing) -> "block " ++ show blkNo
        (Nothing, Just slotNo) -> "slot " ++ show slotNo
        (Nothing, Nothing) -> "-1 (genesis)"


getLatestPoints :: IO [Point (ByronBlockOrEBB cfg)]
getLatestPoints =
    -- Blocks (and the transactions they contain) are inserted within an SQL transaction.
    -- That means that all the blocks (including their transactions) returned by the query
    -- have been completely inserted.
    -- TODO: Get the security parameter (2160) from the config.
    mapMaybe convert <$> DB.runDbNoLogging (DB.queryLatestBlocks 2160)
  where
    convert :: (Word64, ByteString) -> Maybe (Point (ByronBlockOrEBB cfg))
    convert (slot, hashBlob) =
      fmap (Point . Point.block (SlotNo slot)) (convertHashBlob hashBlob)

    -- in Maybe because the bytestring may not be the right size.
    convertHashBlob :: ByteString -> Maybe ByronHash
    convertHashBlob = fmap (ByronHash . AbstractHash) . digestFromByteString

getCurrentTip :: IO BlockNo
getCurrentTip = do
    maybeTip <- DB.runDbNoLogging DB.queryLatestBlock
    case maybeTip of
      Just tip -> pure $ convert tip
      Nothing -> pure genesisBlockNo
  where
    convert :: DB.Block -> BlockNo
    convert blk =
      case DB.blockSlotNo blk of
        Just slot -> BlockNo slot
        Nothing   -> genesisBlockNo

-- | A 'LocalTxSubmissionClient' that submits transactions reading them from
-- a 'StrictTMVar'.  A real implementation should use a better synchronisation
-- primitive.  This demo creates and empty 'TMVar' in
-- 'muxLocalInitiatorNetworkApplication' above and never fills it with a tx.
--
txSubmissionClient
  :: forall tx reject m. (Monad m, MonadSTM m)
  => StrictTMVar m tx -> LocalTxSubmissionClient tx reject m Void
txSubmissionClient txv = LocalTxSubmissionClient $
    atomically (readTMVar txv) >>= pure . client
  where
    client :: tx -> LocalTxClientStIdle tx reject m Void
    client tx =
      SendMsgSubmitTx tx $ \mbreject -> do
        case mbreject of
          Nothing -> return ()
          Just _r -> return ()
        tx' <- atomically $ readTMVar txv
        pure $ client tx'

localChainSyncCodec
  :: forall blk m. (RunNode blk, MonadST m)
  => NodeConfig (BlockProtocol blk)
  -> Codec (ChainSync blk (Tip blk)) DeserialiseFailure m BSL.ByteString
localChainSyncCodec pInfoConfig =
    codecChainSync
      (nodeEncodeBlock pInfoConfig)
      (nodeDecodeBlock pInfoConfig)
      (encodePoint (nodeEncodeHeaderHash (Proxy @blk)))
      (decodePoint (nodeDecodeHeaderHash (Proxy @blk)))
      (encodeTip   (nodeEncodeHeaderHash (Proxy @blk)))
      (decodeTip   (nodeDecodeHeaderHash (Proxy @blk)))

localTxSubmissionCodec
  :: (RunNode blk, MonadST m)
  => Codec (LocalTxSubmission (GenTx blk) String) DeserialiseFailure m BSL.ByteString
localTxSubmissionCodec =
  codecLocalTxSubmission nodeEncodeGenTx nodeDecodeGenTx Serialise.encode Serialise.decode

-- the SingleTypeQueue can only contain ApplyBlock or RollBackToPoint objects, and never a mix of the 2
-- Finish is in the same type as RollBackToPoint, and will also be exclusive
-- when trying to insert a different one into the queue, you should first wait for the queue to return back to being Empty
data Action = ApplyBlock ((ByronBlockOrEBB ByronConfig), BlockNo) | RollBackToPoint (Point (ByronBlockOrEBB ByronConfig)) | Finish
data OnlyContains = Apply | Other | Empty deriving Eq
data SingleTypeQueue = SingleTypeQueue
  { stqContains :: TVar OnlyContains
  , stqQueue :: TBQueue Action
  }

startDbThread :: Trace IO Text -> SingleTypeQueue -> Metrics -> IO ()
startDbThread trce actionQueue metrics@Metrics{mQueuePre,mQueuePost} = do
  (eActs, oldSize, newSize) <- atomically $ do
    oldSize <- lengthTBQueue (stqQueue actionQueue)
    contents <- readTVar (stqContains actionQueue)
    eActs <- case contents of
      Apply -> do
        actions <- flushTBQueue $ stqQueue actionQueue
        pure $ Right actions
      Other -> do
        action <- readTBQueue (stqQueue actionQueue)
        pure $ Left action
      Empty -> retry
    newSize <- lengthTBQueue (stqQueue actionQueue)
    if (newSize == 0)
      then writeTVar (stqContains actionQueue) Empty
      else pure ()
    pure (eActs, oldSize, newSize)
  Gauge.set (fromIntegral $ oldSize) mQueuePre
  Gauge.set (fromIntegral $ newSize) mQueuePost
  case eActs of
    Right actions -> do
      let
        youSawNothing (ApplyBlock blk) = blk
        blocks = map youSawNothing actions
      insertManyByronBlockOrEBB trce blocks
      startDbThread trce actionQueue metrics
    Left (ApplyBlock (blk, tip)) -> do
      -- should never happen, but i'll still fill it in
      insertByronBlockOrEBB trce blk tip
      startDbThread trce actionQueue metrics
    Left (RollBackToPoint point) -> do
      -- we are requested to roll backward to point 'point', the core
      -- node's chain's tip is 'tip'.
      rollbackToPoint trce point
      startDbThread trce actionQueue metrics
    Left Finish -> pure ()

-- | 'ChainSyncClient' which traces received blocks and ignores when it
-- receives a request to rollbackwar.  A real wallet client should:
--
--  * at startup send the list of points of the chain to help synchronise with
--    the node;
--  * update its state when the client receives next block or is requested to
--    rollback, see 'clientStNext' below.
--
chainSyncClient
  :: forall blk m cfg. (MonadTimer m, MonadIO m, blk ~ ByronBlockOrEBB cfg, ByronGiven, cfg ~ ByronConfig)
  => Trace IO Text -> Metrics -> [Point blk] -> BlockNo -> SingleTypeQueue -> ChainSyncClientPipelined blk (Tip blk) m Void
chainSyncClient _trce Metrics{mNodeHeight,mQueuePostWrite} latestPoints currentTip actionQueue =
    ChainSyncClientPipelined $ pure $
      -- Notify the core node about the our latest points at which we are
      -- synchronised.  This client is not persistent and thus it just
      -- synchronises from the genesis block.  A real implementation should send
      -- a list of points up to a point which is k blocks deep.
      SendMsgFindIntersect
        (if null latestPoints then [genesisPoint] else latestPoints)
        ClientPipelinedStIntersect
          { recvMsgIntersectFound    = \_hdr tip -> pure $ go policy Zero currentTip (tipBlockNo tip)
          , recvMsgIntersectNotFound = \  tip -> pure $ go policy Zero currentTip (tipBlockNo tip)
          }
  where
    policy = pipelineDecisionLowHighMark 1000 10000

    mkClientStNext :: (BlockNo -> Tip blk -> ClientPipelinedStIdle n (ByronBlockOrEBB ByronConfig) (Tip blk) m a) -> ClientStNext n (ByronBlockOrEBB ByronConfig) (Tip (ByronBlockOrEBB ByronConfig)) m a
    mkClientStNext finish = ClientStNext {
      recvMsgRollForward = \blk tip -> do
        liftIO $ do
          Gauge.set (fromIntegral $ unBlockNo $ tipBlockNo tip) mNodeHeight
          newSize <- atomically $ do
            currentState <- readTVar (stqContains actionQueue)
            check ((currentState == Empty) || (currentState == Apply))
            writeTBQueue (stqQueue actionQueue) $ ApplyBlock (blk, (tipBlockNo tip))
            writeTVar (stqContains actionQueue) Apply
            lengthTBQueue (stqQueue actionQueue)
          Gauge.set (fromIntegral newSize) mQueuePostWrite
        pure $ finish (blockNo blk) tip
    , recvMsgRollBackward = \point tip -> do
      newTip <- liftIO $ do
        atomically $ do
          currentState <- readTVar (stqContains actionQueue)
          check (currentState == Empty)
          writeTBQueue (stqQueue actionQueue) $ RollBackToPoint point
          writeTVar (stqContains actionQueue) Other

        getCurrentTip -- TODO
      pure $ finish newTip tip
    }

    go :: MkPipelineDecision -> Nat n -> BlockNo -> BlockNo -> ClientPipelinedStIdle n (ByronBlockOrEBB cfg) (Tip blk) m a
    go mkPipelineDecision n clientTip serverTip =
      case (n, runPipelineDecision mkPipelineDecision n clientTip serverTip) of
        (_Zero, (Request, mkPipelineDecision')) ->
            SendMsgRequestNext clientStNext (pure clientStNext)
          where
            clientStNext = mkClientStNext $ \clientBlockNo newServerTip -> go mkPipelineDecision' n clientBlockNo (tipBlockNo newServerTip)
        (_, (Pipeline, mkPipelineDecision')) ->
          SendMsgRequestNextPipelined
            (go mkPipelineDecision' (Succ n) clientTip serverTip)
        (Succ n', (CollectOrPipeline, mkPipelineDecision')) ->
          CollectResponse
            (Just $ SendMsgRequestNextPipelined $ go mkPipelineDecision' (Succ n) clientTip serverTip)
            (mkClientStNext $ \clientBlockNo newServerTip -> go mkPipelineDecision' n' clientBlockNo (tipBlockNo newServerTip))
        (Succ n', (Collect, mkPipelineDecision')) ->
          CollectResponse
            Nothing
            (mkClientStNext $ \clientBlockNo newServerTip -> go mkPipelineDecision' n' clientBlockNo (tipBlockNo newServerTip))
