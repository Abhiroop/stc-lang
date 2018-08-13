{-# LANGUAGE RankNTypes, ExplicitForAll, OverloadedStrings #-}
module SBFMPerfBenchmark where

import FakeComputation

import Monad.StreamsBasedExplicitAPI
import Monad.StreamsBasedFreeMonad
import Data.Dynamic2

import Data.Time.Clock.POSIX

import Control.Monad.Stream.Par
import Control.Monad.Stream.Chan
import Control.Monad.Stream.PinnedChan
import Control.Monad.Stream

import Control.Monad.State

import GHC.Conc (numCapabilities,setNumCapabilities,getNumCapabilities)


-- General note: For debugging install this: https://hackage.haskell.org/package/threadscope
-- Installing via stack did not work for me. But the following did:
-- - brew install gtk+ gtk-mac-integration
-- - cabal unpack threadscope
-- - cabal new-build --constraint="gtk +have-quartz-gtk"
-- Find the binary in threadscope-0.2.9/dist-newstyle/build/x86_64-osx/ghc-8.2.1/threadscope-0.2.9/build/threadscope/threadscope
-- Then add -eventlog to the ghc-options and run:
-- "stack build && stack exec -- statefulness-perf-exe +RTS -ls -N4 -RTS"

currentTimeMillis = round . (* 1000) <$> getPOSIXTime

-- This does not show pipeline scalability because the RTS detects that we are essentially doing the same thing in every stage of the pipeline.
-- It will create "black holes", i.e., it forces the last 3 stages to wait for the results of the first one then just reuses the result.
pipe4 v = do
  c <- return v
  r0 <- liftWithIndexNamed 0 "perf/wrk-1" work c
  r1 <- liftWithIndexNamed 1 "perf/wrk-2" (work . snd) r0
  r2 <- liftWithIndexNamed 2 "perf/wrk-3" (work . snd) r1
  r3 <- liftWithIndexNamed 3 "perf/wrk-4" (work . snd) r2
  r  <- liftWithIndex 4 snd' r3
  return r

-- Final analysis: Pipeline scalability here only shows when IO (state threads printing results) is involved.
--                 Otherwise the RTS checks that we actually funnel the same data through and will not perform the computation multiple times!

snd' :: (a,b) -> StateT () IO b
snd' = return . snd

fourStepPipeline = smap pipe4

-- This shows that our pipeline parallelism works because every stage of the pipeline does a different operation and as such
-- the RTS can not optimize anything by caching results.
pipe3 v = do
  c <- return v
  r0 <- liftWithIndexNamed 0 "perf/wrk-sin" (gwork sin_iter) c
  r1 <- liftWithIndexNamed 1 "perf/wrk-cos" ((gwork cos_iter) . snd) r0
  r2 <- liftWithIndexNamed 2 "perf/wrk-tan" ((gwork tan_iter) . snd) r1
  r  <- liftWithIndex 3 snd' r2
  return r

threeStepPipeline = smap pipe3

-- Beware: You need to recompile with "-threaded" in order to  enable concurrency!
--         Just changing the cabal file and running `stack test` won't work.
--         Instead always do `stack clean && stack test`
pipe4Test :: MonadStream m => (forall a . m a -> IO a) -> IO ([Float],[Float])
pipe4Test run = do
  let a = 3000000 :: Float
  let b = 20000000 :: Int
  let dataCount = 10
  let inputs = replicate dataCount a
  -- let inputs = [3000000 :: Float, 300004,3000006,30000008]
  let r = wrk_sins b a
  let expectedOutputs = replicate dataCount r
  putStrLn $ "num cores (RTS option): " ++ (show numCapabilities)
  (\x -> putStrLn $ "num cores: " ++ show x) =<< getNumCapabilities
  start <- currentTimeMillis
  result <- run $ runOhuaM (fourStepPipeline =<< sfConst' inputs) $ map toDyn [(0::Int,b),(1,b),(2,b),(3,b),undefined]
  -- result <- run $ runOhuaM (fourStepPipeline =<< sfConst' inputs) $ map toDyn [(0::Int,340::Int),(1,334),(2,356),(3,306),undefined]
  stop <- currentTimeMillis

  putStrLn $ "Exec time [ms]: " ++ (show $ stop - start)
  -- assertEqual "result was wrong." expectedOutputs result
  return (expectedOutputs, result)


pipe3Test :: MonadStream m => (forall a . m a -> IO a) -> IO ([Float],[Float])
pipe3Test run = do
  let a = 3000000 :: Float
  let b = 20000000 :: Int
  let dataCount = 10
  let inputs = replicate dataCount a
  -- let inputs = [3000000 :: Float, 300004,3000006,30000008] -> did not have the desired effect
  let r = wrk_sins b a
  let expectedOutputs = replicate dataCount r
  putStrLn $ "num cores (RTS option): " ++ (show numCapabilities)
  (\x -> putStrLn $ "num cores: " ++ show x) =<< getNumCapabilities
  start <- currentTimeMillis
  result <- run $ runOhuaM (threeStepPipeline =<< sfConst' inputs) $ map toDyn [(0::Int,b),(1,b),(2,b),undefined]
  -- result <- run $ runOhuaM (fourStepPipeline =<< sfConst' inputs) $ map toDyn [(0::Int,340::Int),(1,334),(2,356),(3,306),undefined]
  stop <- currentTimeMillis

  putStrLn $ "Exec time [ms]: " ++ (show $ stop - start)
  -- assertEqual "result was wrong." expectedOutputs result
  return (expectedOutputs, result)

coresTest :: MonadStream m => [Int] -> (forall a . m a -> IO a) -> IO [([Float], [Float])]
coresTest cores runner = mapM runTest cores
  where
    runTest numCores = do
      setNumCapabilities numCores
      pipe4Test runner
      -- pipe3Test runner

      -- TODO validation needed! (for now, check the exec times)

-- log
-- ----
-- with output:
--
-- num cores (RTS option): 1
-- num cores: 1
-- Exec time [ms]: 15575
-- num cores (RTS option): 1
-- num cores: 2
-- Exec time [ms]: 8917
-- num cores (RTS option): 1
-- num cores: 3
-- Exec time [ms]: 7628
-- num cores (RTS option): 1
-- num cores: 4
-- Exec time [ms]: 5857
--
-- without output:
-- num cores (RTS option): 1
-- num cores: 1
-- Exec time [ms]: 15826
-- num cores (RTS option): 1
-- num cores: 2
-- Exec time [ms]: 15880
-- num cores (RTS option): 1
-- num cores: 3
-- Exec time [ms]: 15586
-- num cores (RTS option): 1
-- num cores: 4
-- Exec time [ms]: 15838
--
-- without output (single run with 4 cores to make sure the consecutive runs don't influence each other):
-- num cores (RTS option): 4
-- num cores: 4
-- Exec time [ms]: 15481
--
-- Question:
-- My assumption is that the reason why this does not scale in the case without logging was the
-- black holing thing which computes the stuff once and just reuses it.
-- If this is so then how can we ever be faster in the pipeline parallel case?!
-- It feels more like the 15481 ms are the time needed to really compute everything. If this is the case
-- then I something is going on in the scheduler that I have not understood yet.
-- This claim is supported by the observation that the runtime for the single-threaded case is the same
-- no matter if run with or without output.
