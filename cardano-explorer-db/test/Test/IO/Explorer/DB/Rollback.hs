{-# LANGUAGE ScopedTypeVariables #-}

module Test.IO.Explorer.DB.Rollback
  ( tests
  ) where

import           Control.Monad (void)
import           Control.Monad.IO.Class (MonadIO)
import           Control.Monad.Trans.Reader (ReaderT)

import           Data.Word (Word64)

import           Database.Persist.Sql (SqlBackend)

import           Explorer.DB

import           Test.Tasty (TestTree, testGroup)
import           Test.Tasty.HUnit (testCase)

import           Test.IO.Explorer.DB.Util


tests :: TestTree
tests =
  testGroup "Rollback"
    [ testCase "Can rollback" rollbackTest
    ]


rollbackTest :: IO ()
rollbackTest =
  runDbNoLogging $ do
    -- Delete the blocks if they exist.
    deleteAllBlocksCascade
    setupBlockCount <- queryBlockCount
    assertBool ("Block on setup is " ++ show setupBlockCount ++ " but should be 0.") $ setupBlockCount == 0
    -- Set up state before rollback and assert expected counts.
    createAndInsertBlocks 10
    beforeBlocks <- queryBlockCount
    assertBool ("Block count before rollback is " ++ show beforeBlocks ++ " but should be 10.") $ beforeBlocks == 10
    beforeTxCount <- queryTxCount
    assertBool ("Tx count before rollback is " ++ show beforeTxCount ++ " but should be 9.") $ beforeTxCount == 9
    beforeTxOutCount <- queryTxOutCount
    assertBool ("TxOut count before rollback is " ++ show beforeTxOutCount ++ " but should be 2.") $ beforeTxOutCount == 2
    beforeTxInCount <- queryTxInCount
    assertBool ("TxIn count before rollback is " ++ show beforeTxInCount ++ " but should be 1.") $ beforeTxInCount == 1
    -- Rollback a set of blocks.
    Just blkId <- queryLatestBlockId
    Just pBlkId <- queryWalkChain 5 blkId
    void $ deleteCascadeBlockId pBlkId
    -- Assert the expected final state.
    afterBlocks <- queryBlockCount
    assertBool ("Block count after rollback is " ++ show afterBlocks ++ " but should be 10") $ afterBlocks == 4
    afterTxCount <- queryTxCount
    assertBool ("Tx count after rollback is " ++ show afterTxCount ++ " but should be 10") $ afterTxCount == 1
    afterTxOutCount <- queryTxOutCount
    assertBool ("TxOut count after rollback is " ++ show afterTxOutCount ++ " but should be 1.") $ afterTxOutCount == 1
    afterTxInCount <- queryTxInCount
    assertBool ("TxIn count after rollback is " ++ show afterTxInCount ++ " but should be 0.") $ afterTxInCount == 0

-- -----------------------------------------------------------------------------

queryWalkChain :: MonadIO m => Int -> BlockId -> ReaderT SqlBackend m (Maybe BlockId)
queryWalkChain count blkId
  | count <= 0 = pure $ Just blkId
  | otherwise = do
      mpBlkId <- queryPreviousBlockId blkId
      case mpBlkId of
        Nothing -> pure Nothing
        Just pBlkId -> queryWalkChain (count - 1) pBlkId


createAndInsertBlocks :: MonadIO m => Word64 -> ReaderT SqlBackend m ()
createAndInsertBlocks blockCount =
    void $ loop (0, Nothing, Nothing, Nothing)
  where
    loop
        :: MonadIO m
        => (Word64, Maybe BlockId, Maybe Block, Maybe TxId)
        -> ReaderT SqlBackend m (Word64, Maybe BlockId, Maybe Block, Maybe TxId)
    loop (indx, mPrevId, mPrevBlock, mOutId) =
      if indx < blockCount
        then loop =<< createAndInsert (indx, mPrevId, mPrevBlock, mOutId)
        else pure (0, Nothing, Nothing, Nothing)

    createAndInsert
        :: MonadIO m
        => (Word64, Maybe BlockId, Maybe Block, Maybe TxId)
        -> ReaderT SqlBackend m (Word64, Maybe BlockId, Maybe Block, Maybe TxId)
    createAndInsert (indx, mPrevId, mPrevBlock, mTxOutId) = do
        slid <- insertSlotLeader testSlotLeader
        let newBlock = Block (mkBlockHash indx) (Just indx) indx mPrevId
                        (maybe Nothing (const $ Just (mkMerkelRoot indx)) mPrevBlock)
                        slid 42
        blkId <- insertBlock newBlock
        newMTxOutId <- if indx /= 0
                      then pure mTxOutId
                      else do
                        txId <- insertTx $ Tx (mkTxHash blkId 0) blkId 0
                        void $ insertTxOut (mkTxOut blkId txId)
                        pure $ Just txId
        case (indx, mTxOutId) of
            (8, Just txOutId) -> do
                -- Insert Txs here to test that they are cascade deleted when the blocks
                -- they are associcated with are deleted.

                txId <- head <$> mapM insertTx (mkTxs blkId 8)
                void $ insertTxIn (TxIn txId txOutId 0)
                void $ insertTxOut (mkTxOut blkId txId)
            _ -> pure ()
        pure (indx + 1, Just blkId, Just newBlock, newMTxOutId)
