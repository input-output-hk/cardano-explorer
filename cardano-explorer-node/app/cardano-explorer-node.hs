{-# LANGUAGE NoImplicitPrelude #-}

import           Cardano.Prelude

import           Cardano.Common.Parsers (parseLogConfigFile, parseLogMetrics)
import           Cardano.Config.Partial (PartialCardanoConfiguration (..),
                                         PartialCore (..), PartialNode (..))
import           Cardano.Config.CommonCLI (lastOption, parseGenesisHash,
                                           parseGenesisPath, parseRequireNetworkMagic,
                                           parsePbftSigThreshold, parseSlotLength,
                                           parseSocketDir)
import           Cardano.Config.Types (RequireNetworkMagic)
import           Cardano.Shell.Types (CardanoApplication (..))
import qualified Cardano.Shell.Lib as Shell
import qualified Ouroboros.Consensus.BlockchainTime as Consensus

import           Explorer.DB (MigrationDir (..))
import           Explorer.Node (ExplorerNodeParams (..), NodeLayer (..),
                    initializeAllFeatures)

import           Options.Applicative (Parser, ParserInfo)
import qualified Options.Applicative as Opt

main :: IO ()
main = do
    logConfig <- Opt.execParser opts
    (cardanoFeatures, nodeLayer) <- initializeAllFeatures logConfig
    Shell.runCardanoApplicationWithFeatures cardanoFeatures (cardanoApplication nodeLayer)
  where
    cardanoApplication :: NodeLayer -> CardanoApplication
    cardanoApplication = CardanoApplication . nlRunNode



opts :: ParserInfo ExplorerNodeParams
opts =
  Opt.info (pCommandLine <**> Opt.helper)
    ( Opt.fullDesc
    <> Opt.progDesc "Cardano explorer database node."
    )

pCommandLine :: Parser ExplorerNodeParams
pCommandLine = do
  let pconfig =  createPcc
                        <$> (lastOption parseLogConfigFile)
                        <*> parseLogMetrics
                        <*> parseGenesisHash
                        <*> parseGenesisPath
                        <*> parseSocketDir
                        <*> lastOption (migDir <$> pMigrationDir)
                        <*> parsePbftSigThreshold
                        <*> parseRequireNetworkMagic
                        <*> parseSlotLength
  ExplorerNodeParams <$> pconfig
 where
  -- This merges the command line parsed values
  -- into one `PartialCardanoconfiguration`.
  createPcc
    :: Last FilePath
    -- ^ Log Configuration Path
    -> Last Bool
    -- ^ Capture Log Metrics
    -> Last Text
    -- ^ Genesis Hash
    -> Last FilePath
    -- ^ Genesis Path
    -> Last FilePath
    -- ^ Socket Path
    -> Last FilePath
    -- ^ Migration Directory
    -> Last Double
    -- ^ Signature Threshold
    -> Last RequireNetworkMagic
    -> Last Consensus.SlotLength
    -> PartialCardanoConfiguration
  createPcc
    logConfigFp
    logMetrics
    genHash
    genPath
    socketDir
    migDirectory
    pbftSigThresh
    reqNetMagic
    slotLength = mempty { pccSocketDir = socketDir
                        , pccLogConfig = logConfigFp
                        , pccLogMetrics = logMetrics
                        , pccMigrationDir = migDirectory
                        , pccCore = mempty { pcoGenesisFile = genPath
                                           , pcoGenesisHash = genHash
                                           , pcoPBftSigThd = pbftSigThresh
                                           , pcoRequiresNetworkMagic = reqNetMagic
                                           }
                        , pccNode = mempty { pnoSlotLength = slotLength }
                        }

pMigrationDir :: Parser MigrationDir
pMigrationDir =
  MigrationDir <$> Opt.strOption
    (  Opt.long "schema-dir"
    <> Opt.help "The directory containing the migrations."
    <> Opt.completer (Opt.bashCompleter "directory")
    <> Opt.metavar "FILEPATH"
    )
