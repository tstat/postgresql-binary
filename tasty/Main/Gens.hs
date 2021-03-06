module Main.Gens where

import Main.Prelude hiding (assert, isRight, isLeft, choose)
import Test.QuickCheck hiding (vector)
import Test.QuickCheck.Instances
import JSONAST (JSON)
import qualified Main.PTI as PTI
import qualified Data.Scientific as Scientific
import qualified Data.UUID as UUID
import qualified Data.Vector as Vector
import qualified Rebase.Data.HashMap.Strict as HashMap
import qualified PostgreSQL.Binary.Data as Data
import qualified PostgreSQL.Binary.Encoder as Encoder
import qualified Data.Text as Text
import qualified Data.Aeson as Aeson
import qualified JSONAST


-- * Generators
-------------------------

auto :: Arbitrary a => Gen a
auto =
  arbitrary

json :: Gen JSON
json =
  byDepth 0
  where
    byDepth depth =
      frequency (primitives <> composites)
      where
        primitives =
          map (freq,) [null, bool, number, string]
          where
            freq =
              maxFreq
        composites =
          map (freq,) [array, object]
          where
            freq =
              maxFreq - depth
        maxFreq =
          6
        null =
          pure JSONAST.Null
        bool =
          fmap JSONAST.Bool arbitrary
        number =
          fmap JSONAST.Number arbitrary
        string =
          fmap JSONAST.String text
        array =
          fmap JSONAST.Array (vector (byDepth (succ depth)))
        object =
          fmap JSONAST.Object (hashMap text (byDepth (succ depth)))

vector :: Gen a -> Gen (Vector a)
vector element =
  join $ Vector.replicateM <$> arbitrary <*> pure element

hashMap :: (Eq a, Hashable a) => Gen a -> Gen b -> Gen (HashMap a b)
hashMap key value =
  fmap HashMap.fromList $ join $ replicateM <$> arbitrary <*> pure row
  where
    row =
      (,) <$> key <*> value

aeson :: Gen Aeson.Value
aeson =
  fmap unsafeCoerce json

postgresInt :: (Bounded a, Ord a, Integral a, Arbitrary a) => Gen a
postgresInt =
  arbitrary >>= \x -> if x > halfMaxBound then postgresInt else pure x
  where
    halfMaxBound =
      div maxBound 2

text :: Gen Text
text =
  arbitrary >>= \x -> if Text.find (== '\NUL') x == Nothing then return x else text

char :: Gen Char
char =
  arbitrary >>= \x -> if x /= '\NUL' then return x else char

scientific :: Gen Scientific
scientific =
  Scientific.scientific <$> arbitrary <*> arbitrary

microsTimeOfDay :: Gen TimeOfDay
microsTimeOfDay =
  fmap timeToTimeOfDay $ fmap picosecondsToDiffTime $ fmap (* (10^6)) $ 
    choose (0, (10^6)*24*60*60)

microsLocalTime :: Gen LocalTime
microsLocalTime = 
  LocalTime <$> arbitrary <*> microsTimeOfDay

microsUTCTime :: Gen UTCTime
microsUTCTime =
  localTimeToUTC <$> timeZone <*> microsLocalTime

intervalDiffTime :: Gen DiffTime
intervalDiffTime = do
  unsafeCoerce ((* (10^6)) <$> choose (uMin, uMax) :: Gen Integer)
  where
    uMin = unsafeCoerce minInterval `div` 10^6
    uMax = unsafeCoerce maxInterval `div` 10^6

timeZone :: Gen TimeZone
timeZone =
  minutesToTimeZone <$> choose (- 60 * 12 + 1, 60 * 12)

timetz :: Gen (TimeOfDay, TimeZone)
timetz =
  (,) <$> microsTimeOfDay <*> timeZone

uuid :: Gen UUID.UUID
uuid =
  UUID.fromWords <$> arbitrary <*> arbitrary <*> arbitrary <*> arbitrary

arrayRep :: Gen (Word32, Data.Array)
arrayRep =
  do
    ndims <- choose (1, 4)
    dims <- Vector.replicateM ndims dimGen
    (valueGen', oid, arrayOID) <- valueGen
    values <- Vector.replicateM (dimsToNValues dims) valueGen'
    let nulls = Vector.elem Nothing values
    return (arrayOID, (dims, values, nulls, oid))
  where
    dimGen =
      (,) <$> choose (1, 7) <*> pure 1
    valueGen =
      do
        (pti, gen) <- elements [(PTI.int8, mkGen Encoder.int8_int64),
                                (PTI.bool, mkGen Encoder.bool),
                                (PTI.date, mkGen Encoder.date),
                                (PTI.text, mkGen Encoder.text_strict),
                                (PTI.bytea, mkGen Encoder.bytea_strict)]
        return (gen, PTI.oidWord32 (PTI.ptiOID pti), PTI.oidWord32 (fromJust (PTI.ptiArrayOID pti)))
      where
        mkGen renderer =
          fmap (fmap (convert . renderer)) arbitrary
    dimsToNValues =
      Vector.product . fmap dimensionWidth
      where
        dimensionWidth (x, _) = fromIntegral x

array3 :: Gen a -> Gen [[[a]]]
array3 gen =
  do
    width1 <- choose (1, 10)
    width2 <- choose (1, 10)
    width3 <- choose (1, 10)
    replicateM width1 (replicateM width2 (replicateM width3 gen))


-- * Constants
-------------------------

maxInterval :: DiffTime = 
  unsafeCoerce $ 
    (truncate (1780000 * 365.2425 * 24 * 60 * 60 * 10 ^ 12 :: Rational) :: Integer)

minInterval :: DiffTime = 
  negate maxInterval
