{-# LANGUAGE FlexibleInstances, MultiParamTypeClasses, PolyKinds, TypeOperators, UndecidableInstances #-}
module Control.Effect.NonDet
( NonDet(..)
, Alternative(..)
, runNonDet
, AltH(..)
, runNonDetSplit
, SplitH(..)
) where

import Control.Applicative (Alternative(..), liftA2)
import Control.Effect.Handler
import Control.Effect.Internal
import Control.Effect.NonDet.Internal
import Control.Effect.Sum
import Control.Monad (join)

-- | Run a 'NonDet' effect, collecting all branches’ results into an 'Alternative' functor.
--
--   Using '[]' as the 'Alternative' functor will produce all results, while 'Maybe' will return only the first.
runNonDet :: (Alternative f, Monad f, Traversable f, Effectful sig m) => Eff (AltH f m) a -> m (f a)
runNonDet = runAltH . interpret

newtype AltH f m a = AltH { runAltH :: m (f a) }

instance (Alternative f, Monad f, Traversable f, Effectful sig m) => Carrier (NonDet :+: sig) (AltH f m) where
  gen a = AltH (pure (pure a))
  alg = algND \/ (AltH . alg . handle (pure ()) (fmap join . traverse runAltH))
    where algND Empty = AltH (pure empty)
          algND (Choose k) = AltH (liftA2 (<|>) (runAltH (k True)) (runAltH (k False)))


runNonDetSplit :: Effectful sig m => Eff (SplitH m) a -> m [a]
runNonDetSplit = joinSplitH . interpret

newtype SplitH m a = SplitH { runSplitH :: m (Maybe (a, SplitH m a)) }

joinSplitH :: Monad m => SplitH m a -> m [a]
joinSplitH = (>>= maybe (pure []) (\ (a, q) -> (a :) <$> joinSplitH q)) . runSplitH

instance Monad m => Semigroup (SplitH m a) where
  a <> b = SplitH (runSplitH a >>= maybe (runSplitH b) (\ (a', q) -> pure (Just (a', q <> b))))

instance Monad m => Monoid (SplitH m a) where
  mempty = SplitH (pure Nothing)

instance Effectful sig m => Carrier (NonDet :+: sig) (SplitH m) where
  gen a = SplitH (pure (Just (a, SplitH (pure Nothing))))
  alg = algND \/ (wrap . alg . handle [()] (fmap concat . traverse joinSplitH))
    where algND Empty      = SplitH (pure Nothing)
          algND (Choose k) = SplitH (runSplitH (k True) >>= maybe (runSplitH (k False)) (\ (a, q) -> pure (Just (a, q <> k False))))

          wrap a = SplitH (a >>= \ a' -> case a' of
            []     -> pure Nothing
            a'':as -> pure (Just (a'', wrap (pure as))))
