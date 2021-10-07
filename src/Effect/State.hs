module Effect.State where

import           Control.Concurrent.STM.TVar (stateTVar)
import           Control.Monad               (void)
import           Data.Tuple                  (swap)
import           Data.Typeable               (Typeable)
import           Effect
import           Effect.Internal.Base        (thisIsPureTrustMe)
import           UnliftIO.IORef
import           UnliftIO.MVar
import           UnliftIO.STM

data State s :: Effect where
  Get :: State s m s
  Put :: s -> State s m ()
  State :: (s -> (a, s)) -> State s m a

get :: State s :> es => Eff es s
get = send Get

gets :: State s :> es => (s -> t) -> Eff es t
gets = (<$> get)

put :: State s :> es => s -> Eff es ()
put = send . Put

state :: State s :> es => (s -> (a, s)) -> Eff es a
state = send . State

modify :: State s :> es => (s -> s) -> Eff es ()
modify f = state (((), ) . f)

runLocalState :: forall s es a. Typeable s => s -> Eff (State s ': es) a -> Eff es (a, s)
runLocalState s m = thisIsPureTrustMe do
  rs <- newIORef s
  x <- reinterpret (\case
    Get -> readIORef rs
    Put s' -> writeIORef rs s'
    State f -> do
      s' <- readIORef rs
      let (a, s'') = f s'
      writeIORef rs s''
      pure a) m
  s' <- readIORef rs
  pure (x, s')

runAtomicLocalState :: forall s es a. Typeable s => s -> Eff (State s ': es) a -> Eff es (a, s)
runAtomicLocalState s m = thisIsPureTrustMe do
  rs <- newIORef s
  x <- reinterpret (\case
    Get     -> readIORef rs
    Put s'  -> writeIORef rs s'
    State f -> atomicModifyIORef' rs (swap . f)) m
  s' <- readIORef rs
  pure (x, s')

runSharedState :: forall s es a. Typeable s => s -> Eff (State s ': es) a -> Eff es (a, s)
runSharedState s m = thisIsPureTrustMe do
  rs <- newMVar s
  x <- reinterpret (\case
    Get     -> readMVar rs
    Put s'  -> void $ swapMVar rs $! s'
    State f -> modifyMVar rs \s' -> let (s'', a) = f s' in s `seq` pure (a, s'')) m
  s' <- readMVar rs
  pure (x, s')

runAtomicSharedState :: forall s es a. IOE :> es => Typeable s => s -> Eff (State s ': es) a -> Eff es (a, s)
runAtomicSharedState s m = do
  rs <- newTVarIO s
  x <- interpret (\case
    Get     -> readTVarIO rs
    Put s'  -> atomically $ writeTVar rs s'
    State f -> atomically $ stateTVar rs f) m
  s' <- readTVarIO rs
  pure (x, s')
