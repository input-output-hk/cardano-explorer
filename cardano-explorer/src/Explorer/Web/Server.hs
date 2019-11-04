{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NamedFieldPuns #-}

module Explorer.Web.Server (runServer) where

import           Explorer.DB (Ada, Block (..), TxOut (..),
                    queryLatestBlockId, queryTotalSupply,
                    readPGPassFileEnv, toConnectionString)
import           Explorer.Web.Api            (ExplorerApi, explorerApi)
import           Explorer.Web.ClientTypes (CAddress (..), CAddressSummary (..), CAddressType (..),
                    CBlockEntry (..), CBlockRange (..), CBlockSummary (..), CHash (..),
                    CTxHash (..), CUtxo (..),
                    mkCCoin, adaToCCoin)
import           Explorer.Web.Error (ExplorerError (..))
import           Explorer.Web.Query (queryBlockSummary, queryBlockIdFromHeight, queryUtxoSnapshot)
import           Explorer.Web.API1 (ExplorerApi1Record (..), V1Utxo (..))
import qualified Explorer.Web.API1 as API1
import           Explorer.Web.LegacyApi (ExplorerApiRecord (..))

import           Explorer.Web.Server.BlockPagesTotal
import           Explorer.Web.Server.BlocksPages
import           Explorer.Web.Server.BlocksTxs
import           Explorer.Web.Server.EpochPage
import           Explorer.Web.Server.EpochSlot
import           Explorer.Web.Server.GenesisAddress
import           Explorer.Web.Server.GenesisPages
import           Explorer.Web.Server.GenesisSummary
import           Explorer.Web.Server.StatsTxs
import           Explorer.Web.Server.TxLast
import           Explorer.Web.Server.TxsSummary
import           Explorer.Web.Server.Util

import           Control.Monad.IO.Class      (liftIO)
import           Control.Monad.Logger        (runStdoutLoggingT)
import           Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE)
import           Data.ByteString (ByteString)
import qualified Data.ByteString.Base16 as Base16
import           Data.Text (Text)
import qualified Data.Text.Encoding as Text
import           Data.Word                   (Word64)
import           Network.Wai.Handler.Warp    (run)
import           Servant                     (Application, Handler, Server, serve)
import           Servant.API.Generic         (toServant)
import           Servant.Server.Generic      (AsServerT)
import           Servant.API ((:<|>)((:<|>)))

import           Database.Persist.Postgresql (withPostgresqlConn)
import           Database.Persist.Sql (SqlBackend)


runServer :: IO ()
runServer = do
  putStrLn "Running full server on http://localhost:8100/"
  pgconfig <- readPGPassFileEnv
  runStdoutLoggingT .
    withPostgresqlConn (toConnectionString pgconfig) $ \backend ->
      liftIO $ run 8100 (explorerApp backend)

explorerApp :: SqlBackend -> Application
explorerApp backend = serve explorerApi (explorerHandlers backend)

explorerHandlers :: SqlBackend -> Server ExplorerApi
explorerHandlers backend = (toServant oldHandlers) :<|> (toServant newHandlers)
  where
    oldHandlers = ExplorerApiRecord
      { _totalAda           = totalAda backend
      , _dumpBlockRange     = testDumpBlockRange backend
      , _blocksPages        = blocksPages backend
      , _blocksPagesTotal   = blockPagesTotal backend
      , _blocksSummary      = blocksSummary backend
      , _blocksTxs          = blocksTxs backend
      , _txsLast            = getLastTxs backend
      , _txsSummary         = txsSummary backend
      , _addressSummary     = testAddressSummary backend
      , _addressUtxoBulk    = testAddressUtxoBulk backend
      , _epochPages         = epochPage backend
      , _epochSlots         = epochSlot backend
      , _genesisSummary     = genesisSummary backend
      , _genesisPagesTotal  = genesisPages backend
      , _genesisAddressInfo = genesisAddressInfo backend
      , _statsTxs           = statsTxs backend
      } :: ExplorerApiRecord (AsServerT Handler)
    newHandlers = ExplorerApi1Record
      { _utxoHeight         = getUtxoSnapshotHeight backend
      , _utxoHash           = getUtxoSnapshotHash
      } :: ExplorerApi1Record (AsServerT Handler)

--------------------------------------------------------------------------------
-- sample data --
--------------------------------------------------------------------------------
cTxId :: CTxHash
cTxId = CTxHash $ CHash "not-implemented-yet"

totalAda :: SqlBackend -> Handler (Either ExplorerError Ada)
totalAda backend = Right <$> runQuery backend queryTotalSupply

testDumpBlockRange :: SqlBackend -> CHash -> CHash -> Handler (Either ExplorerError CBlockRange)
testDumpBlockRange backend start _ = do
  edummyBlock <- blocksSummary backend start
  edummyTx <- txsSummary backend cTxId
  case (edummyBlock,edummyTx) of
    (Right dummyBlock, Right dummyTx) ->
      pure $ Right $ CBlockRange
        { cbrBlocks = [ dummyBlock ]
        , cbrTransactions = [ dummyTx ]
        }
    (Left err, _) -> pure $ Left err
    (_, Left err) -> pure $ Left err


hexToBytestring :: Text -> ExceptT ExplorerError Handler ByteString
hexToBytestring text = do
  case Base16.decode (Text.encodeUtf8 text) of
    (blob, "") -> pure blob
    (_partial, remain) -> throwE $ Internal $ "cant parse " <> Text.decodeUtf8 remain <> " as hex"

blocksSummary
    :: SqlBackend -> CHash
    -> Handler (Either ExplorerError CBlockSummary)
blocksSummary backend (CHash blkHashTxt) = runExceptT $ do
  blkHash <- hexToBytestring blkHashTxt
  liftIO $ print (blkHashTxt, blkHash)
  mBlk <- runQuery backend $ queryBlockSummary blkHash
  case mBlk of
    Just (blk, prevHash, nextHash, txCount, fees, totalOut, slh, mts) ->
      case blockSlotNo blk of
        Just slotno -> do
          let (epoch, slot) = slotno `divMod` slotsPerEpoch
          pure $ CBlockSummary
            { cbsEntry = CBlockEntry
               { cbeEpoch = epoch
               , cbeSlot = fromIntegral slot
               -- Use '0' for EBBs.
               , cbeBlkHeight = maybe 0 fromIntegral $ blockBlockNo blk
               , cbeBlkHash = CHash . bsBase16Encode $ blockHash blk
               , cbeTimeIssued = mts
               , cbeTxNum = txCount
               , cbeTotalSent = adaToCCoin totalOut
               , cbeSize = blockSize blk
               , cbeBlockLead = Just $ bsBase16Encode slh
               , cbeFees = adaToCCoin fees
               }
            , cbsPrevHash = CHash $ bsBase16Encode prevHash
            , cbsNextHash = fmap (CHash . bsBase16Encode) nextHash
            , cbsMerkleRoot = CHash $ maybe "" bsBase16Encode (blockMerkelRoot blk)
            }
        Nothing -> throwE $ Internal "slot missing"
    _ -> throwE $ Internal "No block found"

sampleAddressSummary :: CAddressSummary
sampleAddressSummary = CAddressSummary
    { caAddress = CAddress "not-implemented-yet"
    , caType    = CPubKeyAddress
    , caTxNum   = 0
    , caBalance = mkCCoin 0
    , caTxList  = []
    , caTotalInput = mkCCoin 0
    , caTotalOutput = mkCCoin 0
    , caTotalFee = mkCCoin 0
    }

testAddressSummary
    :: SqlBackend -> CAddress
    -> Handler (Either ExplorerError CAddressSummary)
testAddressSummary _backend _  = pure $ Right sampleAddressSummary

testAddressUtxoBulk
    :: SqlBackend -> [CAddress]
    -> Handler (Either ExplorerError [CUtxo])
testAddressUtxoBulk _backend _  =
    pure $ Right
            [CUtxo (CTxHash $ CHash "not-implemented-yet") 0 (CAddress "not-implemented-yet") (mkCCoin 3)
            ]

getUtxoSnapshotHeight :: SqlBackend -> Maybe Word64 -> Handler (Either ExplorerError [V1Utxo])
getUtxoSnapshotHeight backend mHeight = runExceptT $ do
  liftIO $ putStrLn "getting snapshot by height"
  outputs <- ExceptT <$> runQuery backend $ do
    mBlkid <- case mHeight of
      Just height -> queryBlockIdFromHeight height
      Nothing -> queryLatestBlockId
    case mBlkid of
      Just blkid -> Right <$> queryUtxoSnapshot blkid
      Nothing -> pure $ Left $ Internal "block not found at given height"
  let
    convertRow :: (TxOut, ByteString) -> V1Utxo
    convertRow (txout, txhash) = V1Utxo
      { API1.cuId = (CTxHash . CHash . Text.decodeUtf8) txhash
      , API1.cuOutIndex = txOutIndex txout
      , API1.cuAddress = (CAddress . txOutAddress) txout
      , API1.cuCoins = (mkCCoin . fromIntegral . txOutValue) txout
      }
  pure $ map convertRow outputs

getUtxoSnapshotHash :: Maybe CHash -> Handler (Either ExplorerError [V1Utxo])
getUtxoSnapshotHash _ = runExceptT $ do
  liftIO $ putStrLn "getting snapshot by hash"
  -- queryBlockId
  pure []
