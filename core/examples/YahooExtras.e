module YahooExtras where

import IO
import Maybe
import Syntax.IO
import Control.Monad
import Control.Functor
import Function

mmap2 = liftA2 maybeAp
iomap = fmap ioFunctor
iobind = bind ioMonad

combineIoMaybe : (a -> b -> c) -> IO (Maybe a) -> IO (Maybe b) -> IO (Maybe c)
combineIoMaybe f iom1 iom2 = iom1 >>= (ma -> iomap (mb -> mmap2 f ma mb) iom2)
