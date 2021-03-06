module Sound.Tidal.Time where

-- | Time is represented by a rational number. Each natural number
-- represents both the start of the next rhythmic cycle, and the end
-- of the previous one. Rational numbers are used so that subdivisions
-- of each cycle can be accurately represented.
type Time = Rational

-- | @(s,e) :: Arc@ represents a time interval with a start and end value.
-- @ { t : s <= t && t < e } @
type Arc = (Time, Time)

-- | An Event is a value that occurs during the given @Arc@
type Event a = (Arc, a)

-- | The starting point of the current cycle. A cycle occurs from each
-- natural number to the next, so this is equivalent to @floor@.
sam :: Time -> Time
sam = fromIntegral . floor

-- | The end point of the current cycle (and starting point of the next cycle)
nextSam :: Time -> Time
nextSam = (1+) . sam


-- | The position of a time value relative to the start of its cycle.
cyclePos :: Time -> Time
cyclePos t = t - sam t

-- | @isIn a t@ is @True@ iff @t@ is inside 
-- the arc represented by @a@.
isIn :: Arc -> Time -> Bool
isIn (s,e) t = t >= s && t < e

-- | Splits the given @Arc@ into a list of @Arc@s, at cycle boundaries.
arcCycles :: Arc -> [Arc]
arcCycles (s,e) | s >= e = []
                | sam s == sam e = [(s,e)]
                | otherwise = (s, nextSam s) : (arcCycles (nextSam s, e))


-- | @subArc i j@ is the arc that is the intersection of @i@ and @j@.
subArc :: Arc -> Arc -> Maybe Arc
subArc (s, e) (s',e') | s'' < e'' = Just (s'', e'')
                      | otherwise = Nothing
  where s'' = max s s'
        e'' = min e e'

-- | Map the given function over both the start and end @Time@ values
-- of the given @Arc@.
mapArc :: (Time -> Time) -> Arc -> Arc
mapArc f (s,e) = (f s, f e)

-- | Returns the `mirror image' of an @Arc@, used by @Sound.Tidal.Pattern.rev@.
mirrorArc :: Arc -> Arc
mirrorArc (s, e) = (sam s + (nextSam s - e), nextSam s - (s - sam s))

-- | The start time of the given @Event@
eventStart :: Event a -> Time
eventStart = fst . fst

-- | The midpoint of an @Arc@
midPoint :: Arc -> Time
midPoint (s,e) = s + ((e - s) / 2)
