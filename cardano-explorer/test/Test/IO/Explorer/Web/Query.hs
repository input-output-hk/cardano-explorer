{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# OPTIONS_GHC -Wno-error=orphans #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Test.IO.Explorer.Web.Query where

import           Test.Tasty (TestTree, testGroup)
import           Test.Tasty.HUnit (testCase)

import           Explorer.DB
import           Explorer.Web.Query
import           Test.IO.Explorer.DB.Util (testSlotLeader, assertBool, mkBlockHash)

import           Control.Monad.IO.Class (liftIO)
import           Control.Monad.Logger
import           Control.Monad.Trans.Reader
import           Data.ByteString.Char8 (ByteString)
import qualified Data.ByteString.Char8 as BS
import           Data.Text (Text)
import           Data.Text.Encoding (decodeUtf8)
import           Data.Word (Word16, Word64)
import           Database.Persist.Postgresql

tests :: TestTree
tests =
  testGroup "Web.Query"
    [ testCase "case 1" testCase1
    , testCase "empty utxo with empty db" testEmptyUtxo
    ]

dropAndRemakeDb :: IO PGConfig
dropAndRemakeDb = do
  pgconfig' <- readPGPassFileEnv
  let
    pgconfig = pgconfig' { pgcDbname = (pgcDbname pgconfig') <> "-tests" }
    pgconfigExternal = pgconfig' { pgcDbname = "postgres" }
    --debug :: MonadLogger m => String -> m ()
    --debug = monadLoggerLog defaultLoc "" LevelDebug
    -- ran outside a transaction
    runExternalSql :: Text -> [PersistValue] -> IO ()
    runExternalSql sql params =
      runStdoutLoggingT . withPostgresqlConn (toConnectionString pgconfigExternal) $ \backend ->
        flip runReaderT backend $
          rawExecute sql params
  putStrLn "dropping old test db"
  runExternalSql ("DROP DATABASE IF EXISTS \"" <> (decodeUtf8 $ pgcDbname pgconfig) <> "\"") []
  putStrLn "remaking db"
  runExternalSql ("CREATE DATABASE \"" <> (decodeUtf8 $ pgcDbname pgconfig) <> "\"") []
  putStrLn "doing test"
  runMigrations (\oldcfg -> oldcfg { pgcDbname = pgcDbname pgconfig }) True (MigrationDir "../schema") (LogFileDir "/tmp")
  pure pgconfig

dropAndRemakeDbThenTest :: ReaderT SqlBackend (LoggingT IO) () -> IO ()
dropAndRemakeDbThenTest action = do
  pgconfig <- dropAndRemakeDb
  runStdoutLoggingT . withPostgresqlConn (toConnectionString pgconfig) $ \backend -> do
    -- ran inside a transaction
    flip runSqlConn backend action

testEmptyUtxo :: IO ()
testEmptyUtxo = do
  dropAndRemakeDbThenTest $ do
    slid <- insertSlotLeader testSlotLeader
    bid0 <- insertBlock (blockZero slid)
    snapshot <- queryUtxoSnapshot bid0
    liftIO $ print snapshot
    assertBool "snapshot should be empty" (snapshot == [])

testCase1 :: IO ()
testCase1 = do
  dropAndRemakeDbThenTest $ do
    slid <- insertSlotLeader testSlotLeader
    bid0 <- insertBlock $ blockZero slid

    snapshot00 <- queryUtxoSnapshot bid0
    assertBool "utxo must be empty when no outputs exist" (snapshot00 == [])

    bid1 <- insertBlock $ mkBlock 1 slid bid0
    let tx0 = mkTx 0 bid1
    tx0id <- insertTx tx0
    let
      out0 = mkOut tx0id 0 "tx0 out0" 123
      out1 = mkOut tx0id 1 "tx0 out1" 123
      expected1 =
        [ (out0, txHash tx0)
        , (out1, txHash tx0)
        ]
    mapM_ insertTxOut [ out0, out1 ]

    snapshot01 <- queryUtxoSnapshot bid0
    assertBool "snapshot at point 0 must not change when inserting new blocks" (snapshot00 == snapshot01)
    snapshot10 <- queryUtxoSnapshot bid1
    assertBool "snapshot at point 1 should be expected value" (snapshot10 == expected1)

    bid2 <- insertBlock $ mkBlock 2 slid bid1
    let tx1 = mkTx 1 bid2
    tx1id <- insertTx tx1
    let
      out2 = mkOut tx1id 0 "tx1 out0" 123
      expected2 =
        [ (out1, txHash tx0)
        , (out2, txHash tx1)
        ]
    _ <- insertTxIn $ mkIn tx1id (tx0id, 0)
    _ <- insertTxOut out2

    snapshot02 <- queryUtxoSnapshot bid0
    snapshot11 <- queryUtxoSnapshot bid1
    snapshot20 <- queryUtxoSnapshot bid2
    assertBool "snapshot at point 0 must not change when inserting new blocks" (snapshot00 == snapshot02)
    assertBool "snapshot at point 1 must not change when inserting new blocks" (snapshot10 == snapshot11)
    assertBool "snapshot at point 2 should be expected value" (snapshot20 == expected2)

    bid3 <- insertBlock $ mkBlock 3 slid bid2
    let tx2 = mkTx 2 bid3
    tx2id <- insertTx tx2
    let
      out3 = mkOut tx2id 0 "tx2 out0" 123
      expected3 =
        [ (out1, txHash tx0)
        , (out2, txHash tx1)
        , (out3, txHash tx2)
        ]
    _ <- insertTxOut out3

    snapshot03 <- queryUtxoSnapshot bid0
    snapshot12 <- queryUtxoSnapshot bid1
    snapshot21 <- queryUtxoSnapshot bid2
    snapshot30 <- queryUtxoSnapshot bid3
    assertBool "snapshot at point 0 must not change when inserting new blocks" (snapshot00 == snapshot03)
    assertBool "snapshot at point 1 must not change when inserting new blocks" (snapshot10 == snapshot12)
    assertBool "snapshot at point 2 must not change when inserting new blocks" (snapshot20 == snapshot21)
    assertBool "snapshot at point 3 should be expected value" (snapshot30 == expected3)

deriving instance Show TxOut
deriving instance Eq TxOut

blockZero :: SlotLeaderId -> Block
blockZero slid =
  Block (mkHash '\0') Nothing Nothing Nothing Nothing Nothing slid 0

mkHash :: Char -> ByteString
mkHash = BS.pack . replicate 32

mkBlock :: Word64 -> SlotLeaderId -> BlockId -> Block
mkBlock blk slid previous =
  Block (mkBlockHash blk) Nothing Nothing (Just blk) (Just previous) Nothing slid 0

-- TODO, make a `mkTxHash`, so the tx hashes dont claim `block #0`
mkTx :: Word64 -> BlockId -> Tx
mkTx txnum block = Tx (mkBlockHash txnum) block 0

mkOut :: TxId -> Word16 -> Text -> Word64 -> TxOut
mkOut txid index addr value = TxOut txid index addr value

mkIn :: TxId -- the tx spending this input
  -> (TxId, Word16) -- the index of, an output, and the tx to find it in
  -> TxIn
mkIn parent (outtx, outidx) = TxIn parent outtx outidx
