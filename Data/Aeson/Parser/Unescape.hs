{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE MagicHash                #-}
{-# LANGUAGE UnliftedFFITypes         #-}

module Data.Aeson.Parser.Unescape (
  unescapeTextScanner
, unescapeText
) where

import           Control.Exception          (evaluate, throw, try)
import           Control.Monad.ST.Unsafe    (unsafeIOToST, unsafeSTToIO)
import           Data.ByteString.Internal   (ByteString(..))
import qualified Data.Text.Array            as A
import           Data.Text.Encoding.Error   (UnicodeException (..))
import           Data.Text.Internal         (Text (..))
import           Data.Text.Internal.Private (runText)
import           Data.Text.Unsafe           (unsafeDupablePerformIO)
import           Data.Word                  (Word8)
import           Foreign.C.Types            (CInt (..), CSize (..))
import           Foreign.ForeignPtr         (withForeignPtr)
import           Foreign.Marshal.Utils      (with)
import           Foreign.Ptr                (Ptr, plusPtr)
import           Foreign.Storable           (peek)
import           GHC.Base                   (MutableByteArray#)

foreign import ccall unsafe "_js_decode_string" c_js_decode
    :: MutableByteArray# s -> Ptr CSize
    -> Ptr Word8 -> Ptr Word8 -> IO CInt

foreign import ccall unsafe "_js_find_string_end" c_js_find_string_end
    :: CInt -> Ptr Word8 -> Ptr Word8 -> IO CInt

unescapeTextScanner :: CInt -> ByteString -> Either CInt (ByteString, ByteString)
unescapeTextScanner backslashed bs@(PS fp off len) = unsafeDupablePerformIO $
    withForeignPtr fp $ \ptr -> do
        s <- c_js_find_string_end backslashed (ptr `plusPtr` off) (ptr `plusPtr` (off + len))
        if s >= 0
            then let s' = fromIntegral s
                 in return $ Right (PS fp off s', PS fp (off + s') (len - s'))
            else return (Left s)
{-# INLINE unescapeTextScanner #-}

unescapeText' :: ByteString -> Text
unescapeText' (PS fp off len) = runText $ \done -> do
  let go dest = withForeignPtr fp $ \ptr ->
        with (0::CSize) $ \destOffPtr -> do
          let end = ptr `plusPtr` (off + len)
              loop curPtr = do
                res <- c_js_decode (A.maBA dest) destOffPtr curPtr end
                case res of
                  0 -> do
                    n <- peek destOffPtr
                    unsafeSTToIO (done dest (fromIntegral n))
                  _ ->
                    throw (DecodeError desc Nothing)
          loop (ptr `plusPtr` off)
  (unsafeIOToST . go) =<< A.new len
 where
  desc = "Data.Text.Internal.Encoding.decodeUtf8: Invalid UTF-8 stream"
{-# INLINE unescapeText' #-}

unescapeText :: ByteString -> Either UnicodeException Text
unescapeText = unsafeDupablePerformIO . try . evaluate . unescapeText'
{-# INLINE unescapeText #-}
