{-# LANGUAGE DeriveDataTypeable #-}

module Sound.Tidal.Pattern where

import Control.Applicative
import Data.Monoid
import Data.Fixed
import Data.List
import Data.Maybe
import Data.Ratio
import Debug.Trace
import Data.Typeable
import Data.Function
import System.Random.Mersenne.Pure64

import Sound.Tidal.Time
import Sound.Tidal.Utils

-- | The pattern datatype, a function from a time @Arc@ to @Event@
-- values. For discrete patterns, this returns the events which are
-- active during that time. For continuous patterns, events with
-- values for the midpoint of the given @Arc@ is returned.

data Pattern a = Pattern {arc :: Arc -> [Event a]}

-- | @show (p :: Pattern)@ returns a text string representing the
-- event values active during the first cycle of the given pattern.

instance (Show a) => Show (Pattern a) where
  show p@(Pattern _) = show $ arc p (0, 1)

instance Functor Pattern where
  fmap f (Pattern a) = Pattern $ fmap (fmap (mapSnd f)) a

-- | @pure a@ returns a pattern with an event with value @a@, which
-- has a duration of one cycle, and repeats every cycle.
instance Applicative Pattern where
  pure x = Pattern $ \(s, e) -> map 
                                (\t -> ((t%1, (t+1)%1), x)) 
                                [floor s .. ((ceiling e) - 1)]
  (Pattern fs) <*> (Pattern xs) = 
    Pattern $ \a -> concatMap applyX (fs a)
    where applyX ((s,e), f) = 
            map (\(_, x) -> ((s,e), f x)) 
                (filter 
                 (\(a', _) -> isIn a' s)
                 (xs (s,e))
                )

-- | @mempty@ is a synonym for @silence@.
-- | @mappend@ is a synonym for @overlay@.
instance Monoid (Pattern a) where
    mempty = silence
    mappend x y = Pattern $ \a -> (arc x a) ++ (arc y a)


instance Monad Pattern where
  return = pure
  p >>= f = 
    Pattern (\a -> concatMap
                   (\((s,e), x) -> mapFsts (const (s,e)) $
                                   filter
                                   (\(a', _) -> isIn a' s)
                                   (arc (f x) (s,e))
                   )
                   (arc p a)
             )

-- | @atom@ is a synonym for @pure@.
atom :: a -> Pattern a
atom = pure

-- | @silence@ returns a pattern with no events.
silence :: Pattern a
silence = Pattern $ const []

-- | @mapQueryArc f p@ returns a new @Pattern@ with function @f@
-- applied to the @Arc@ values passed to the original @Pattern@ @p@.
mapQueryArc :: (Arc -> Arc) -> Pattern a -> Pattern a
mapQueryArc f p = Pattern $ \a -> arc p (f a)

-- | @mapQueryTime f p@ returns a new @Pattern@ with function @f@
-- applied to the both the start and end @Time@ of the @Arc@ passed to
-- @Pattern@ @p@.
mapQueryTime :: (Time -> Time) -> Pattern a -> Pattern a
mapQueryTime = mapQueryArc . mapArc

-- | @mapResultArc f p@ returns a new @Pattern@ with function @f@
-- applied to the @Arc@ values in the events returned from the
-- original @Pattern@ @p@.
mapResultArc :: (Arc -> Arc) -> Pattern a -> Pattern a
mapResultArc f p = Pattern $ \a -> mapFsts f $ arc p a

-- | @mapResultTime f p@ returns a new @Pattern@ with function @f@
-- applied to the both the start and end @Time@ of the @Arc@ values in
-- the events returned from the original @Pattern@ @p@.
mapResultTime :: (Time -> Time) -> Pattern a -> Pattern a
mapResultTime = mapResultArc . mapArc

-- | @overlay@ combines two @Pattern@s into a new pattern, so that
-- their events are combined over time.
overlay :: Pattern a -> Pattern a -> Pattern a
overlay p p' = Pattern $ \a -> (arc p a) ++ (arc p' a)
(>+<) = overlay

-- | @stack@ combines a list of @Pattern@s into a new pattern, so that
-- their events are combined over time.
stack :: [Pattern a] -> Pattern a
stack ps = foldr overlay silence ps

-- | @append@ combines two patterns @Pattern@s into a new pattern, so
-- that the events of the second pattern are appended to those of the
-- first pattern, within a single cycle

append :: Pattern a -> Pattern a -> Pattern a
append a b = cat [a,b]

-- | @append'@ does the same as @append@, but over two cycles, so that
-- the cycles alternate between the two patterns.
append' :: Pattern a -> Pattern a -> Pattern a
append' a b  = slow 2 $ cat [a,b]

-- | @cat@ returns a new pattern which interlaces the cycles of the
-- given patterns, within a single cycle. It's the equivalent of
-- @append@, but with a list of patterns.
cat :: [Pattern a] -> Pattern a
cat ps = density (fromIntegral $ length ps) $ slowcat ps

{-slowcat' ps = Pattern $ \a -> concatMap f (arcCycles a)
  where l = length ps
        f (s,e) = arc p (s,e)
          where p = ps !! n
                n = (floor s) `mod` l-}

-- Concatenates so that the first loop of each pattern is played in
-- turn, second loop of each pattern, and so on..

-- | @slowcat@ does the same as @cat@, but maintaining the duration of
-- the original patterns. It is the equivalent of @append'@, but with
-- a list of patterns.

slowcat :: [Pattern a] -> Pattern a
slowcat [] = silence
slowcat ps = Pattern $ \a -> concatMap f (arcCycles a)
  where l = length ps
        f (s,e) = arc (mapResultTime (+offset) p) (s',e')
          where p = ps !! n
                r = (floor s) :: Int
                n = (r `mod` l) :: Int
                offset = (fromIntegral $ r - ((r - n) `div` l)) :: Time
                (s', e') = (s-offset, e-offset)

-- | @listToPat@ turns the given list of values to a Pattern, which
-- cycles through the list.
listToPat :: [a] -> Pattern a
listToPat = cat . map atom

-- | @maybeListToPat@ is similar to @listToPat@, but allows values to
-- be optional using the @Maybe@ type, so that @Nothing@ results in
-- gaps in the pattern.
maybeListToPat :: [Maybe a] -> Pattern a
maybeListToPat = cat . map f
  where f Nothing = silence
        f (Just x) = atom x

-- | @run@ @n@ returns a pattern representing a cycle of numbers from @0@ to @n-1@.
run n = listToPat [0 .. n-1]

-- | @density@ returns the given pattern with density increased by the
-- given @Time@ factor. Therefore @density 2 p@ will return a pattern
-- that is twice as fast, and @density (1%3) p@ will return one three
-- times as slow.
density :: Time -> Pattern a -> Pattern a
density 0 p = p
density 1 p = p
density r p = mapResultTime (/ r) $ mapQueryTime (* r) p

-- | @slow@ does the opposite of @density@, i.e. @slow 2 p@ will
-- return a pattern that is half the speed.
slow :: Time -> Pattern a -> Pattern a
slow 0 = id
slow t = density (1/t) 


-- | The @<~@ operator shift (or rotate) a pattern to the left (or
-- counter-clockwise) by the given @Time@ value. For example 
-- @(1%16) <~ p@ will return a pattern with all the events moved 
-- one 16th of a cycle to the left.
(<~) :: Time -> Pattern a -> Pattern a
(<~) t p = filterOffsets $ mapResultTime (+ t) $ mapQueryTime (subtract t) p

-- | The @~>@ operator does the same as @~>@ but shifts events to the
-- right (or clockwise) rather than to the left.
(~>) :: Time -> Pattern a -> Pattern a
(~>) = (<~) . (0-)

-- | @rev p@ returns @p@ with the event positions in each cycle
-- reversed (or mirrored).
rev :: Pattern a -> Pattern a
rev p = Pattern $ \a -> concatMap 
                        (\a' -> mapFsts mirrorArc $ 
                                (arc p (mirrorArc a')))
                        (arcCycles a)

-- | @palindrome p@ applies @rev@ to @p@ every other cycle, so that
-- the pattern alternates between forwards and backwards.
palindrome p = append' p (rev p)

-- | @when test f p@ applies the function @f@ to @p@, but in a way
-- which only affects cycles where the @test@ function applied to the
-- cycle number returns @True@.
when :: (Int -> Bool) -> (Pattern a -> Pattern a) ->  Pattern a -> Pattern a
when test f p = Pattern $ \a -> concatMap apply (arcCycles a)
  where apply a | test (floor $ fst a) = (arc $ f p) a
                | otherwise = (arc p) a

-- | @every n f p@ applies the function @f@ to @p@, but only affects
-- every @n@ cycles.
every :: Int -> (Pattern a -> Pattern a) -> Pattern a -> Pattern a
every 0 f p = p
every n f p = when ((== 0) . (`mod` n)) f p

-- | @sig f@ takes a function from time to values, and turns it into a
-- @Pattern@.
sig :: (Time -> a) -> Pattern a
sig f = Pattern f'
  where f' (s,e) | s > e = []
                 | otherwise = [((s,e), f s)]

-- | @sinewave@ returns a @Pattern@ of continuous @Double@ values following a
-- sinewave with frequency of one cycle, and amplitude from -1 to 1.
sinewave :: Pattern Double
sinewave = sig $ \t -> sin $ pi * 2 * (fromRational t)
-- | @sine@ is a synonym for @sinewave.
sine = sinewave
-- | @sinerat@ is equivalent to @sinewave@ for @Rational@ values,
-- suitable for use as @Time@ offsets.
sinerat = fmap toRational sine
ratsine = sinerat

-- | @sinewave1@ is equivalent to @sinewave@, but with amplitude from 0 to 1.
sinewave1 :: Pattern Double
sinewave1 = fmap ((/ 2) . (+ 1)) sinewave

-- | @sine1@ is a synonym for @sinewave1@.
sine1 = sinewave1

-- | @sinerat1@ is equivalent to @sinerat@, but with amplitude from 0 to 1.
sinerat1 = fmap toRational sine1

-- | @sineAmp1 d@ returns @sinewave1@ with its amplitude offset by @d@.
sineAmp1 :: Double -> Pattern Double
sineAmp1 offset = (+ offset) <$> sinewave1

-- | @sawwave@ is the equivalent of @sinewave@ for sawtooth waves.
sawwave :: Pattern Double
sawwave = ((subtract 1) . (* 2)) <$> sawwave1

-- | @saw@ is a synonym for @sawwave@.
saw = sawwave

-- | @sawrat@ is the same as @sawwave@ but returns @Rational@ values
-- suitable for use as @Time@ offsets.
sawrat = fmap toRational saw

sawwave1 :: Pattern Double
sawwave1 = sig $ \t -> mod' (fromRational t) 1
saw1 = sawwave1
sawrat1 = fmap toRational saw1

-- | @triwave@ is the equivalent of @sinewave@ for triangular waves.
triwave :: Pattern Double
triwave = ((subtract 1) . (* 2)) <$> triwave1

-- | @tri@ is a synonym for @triwave@.
tri = triwave

-- | @trirat@ is the same as @triwave@ but returns @Rational@ values
-- suitable for use as @Time@ offsets.
trirat = fmap toRational tri

triwave1 :: Pattern Double
triwave1 = append sawwave1 (rev sawwave1)

tri1 = triwave1
trirat1 = fmap toRational tri1


-- todo - triangular waves again

squarewave1 :: Pattern Double
squarewave1 = sig $ 
              \t -> fromIntegral $ floor $ (mod' (fromRational t) 1) * 2
square1 = squarewave1

squarewave :: Pattern Double
squarewave = ((subtract 1) . (* 2)) <$> squarewave1
square = squarewave

-- Filter out events that start before range
filterOffsets :: Pattern a -> Pattern a
filterOffsets (Pattern f) = 
  Pattern $ \(s, e) -> filter ((>= s) . eventStart) $ f (s, e)

seqToRelOnsets :: Arc -> Pattern a -> [(Double, a)]
seqToRelOnsets (s, e) p = mapFsts (fromRational . (/ (e-s)) . (subtract s) . fst) $ arc (filterOffsets p) (s, e)

segment :: Pattern a -> Pattern [a]
segment p = Pattern $ \(s,e) -> filter (\((s',e'),_) -> s' < e && e' > s) $ groupByTime (segment' (arc p (s,e)))

segment' :: [Event a] -> [Event a]
segment' es = foldr split es pts
  where pts = nub $ points es

split :: Time -> [Event a] -> [Event a]
split _ [] = []
split t ((ev@((s,e), v)):es) | t > s && t < e = ((s,t),v):((t,e),v):(split t es)
                             | otherwise = ev:split t es

points :: [Event a] -> [Time]
points [] = []
points (((s,e), _):es) = s:e:(points es)

groupByTime :: [Event a] -> [Event [a]]
groupByTime es = map mrg $ groupBy ((==) `on` fst) $ sortBy (compare `on` fst) es
  where mrg es@((a, _):_) = (a, map snd es)

ifp :: (Int -> Bool) -> (Pattern a -> Pattern a) -> (Pattern a -> Pattern a) -> Pattern a -> Pattern a
ifp test f1 f2 p = Pattern $ \a -> concatMap apply (arcCycles a)
  where apply a | test (floor $ fst a) = (arc $ f1 p) a
                | otherwise = (arc $ f2 p) a

rand :: Pattern Double
rand = Pattern $ \a -> [(a, fst $ randomDouble $ pureMT $ floor $ (*1000000) $ (midPoint a))]
