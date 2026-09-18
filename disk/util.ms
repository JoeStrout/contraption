// util.ms
// Identity-based list operations.
//
// MiniScript's == compares maps by value, so list.indexOf would happily match
// two distinct parts that merely look alike -- two balls of the same size and
// color, say.  Worse, parts hold a reference back to the world, which holds
// the list of parts, so a deep compare is expensive and cyclic.  Anywhere we
// mean "this exact object", we go through refEquals.

indexOfRef = function(lst, item)
	for i in lst.indexes
		if refEquals(lst[i], item) then return i
	end for
	return null
end function

removeRef = function(lst, item)
	i = indexOfRef(lst, item)
	if i != null then lst.remove i
	return i != null
end function

containsRef = function(lst, item)
	return indexOfRef(lst, item) != null
end function

// refEquals on two nulls is true, which is what we want for "same selection".
sameRef = function(a, b)
	if a == null or b == null then return a == null and b == null
	return refEquals(a, b)
end function

//----------------------------------------------------------------------
// Small geometry helpers, for the parts that draw themselves rather than
// hand the job to a sprite.
//----------------------------------------------------------------------

// The unit vector along (dx, dy), or null if there is no direction to speak
// of.  Callers use the null to mean "degenerate, skip it".
unit = function(dx, dy)
	d = sqrt(dx * dx + dy * dy)
	if d < 0.0001 then return null
	return [dx / d, dy / d]
end function

// How far (x, y) is from the segment a-b.
distToSegment = function(x, y, a, b)
	dx = b[0] - a[0]; dy = b[1] - a[1]
	len2 = dx * dx + dy * dy
	if len2 < 0.0001 then return sqrt((x - a[0]) ^ 2 + (y - a[1]) ^ 2)
	t = ((x - a[0]) * dx + (y - a[1]) * dy) / len2
	if t < 0 then t = 0
	if t > 1 then t = 1
	return sqrt((x - a[0] - dx * t) ^ 2 + (y - a[1] - dy * t) ^ 2)
end function

//----------------------------------------------------------------------
// Polylines: a plain list of [x, y], measured and cut up.  Written for the
// fuse, which is a line pinned to the board with pieces eaten off each end,
// and wanted since by anything else that has to walk a drawn line -- an
// explosive's own little fuse among them.  None of it knows what a part is.
//----------------------------------------------------------------------

segLen = function(a, b)
	return sqrt((b[0] - a[0]) ^ 2 + (b[1] - a[1]) ^ 2)
end function

polyLength = function(pts)
	if pts == null or pts.len < 2 then return 0
	total = 0
	for i in range(1, pts.len - 1, 1)
		total = total + segLen(pts[i-1], pts[i])
	end for
	return total
end function

lerpPt = function(a, b, f)
	return [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f]
end function

// The piece of a polyline between two distances along it, or null if that is
// nothing at all.
trimPoly = function(pts, fromS, toS)
	if pts == null or pts.len < 2 or toS <= fromS then return null
	out = []
	s = 0
	for i in range(1, pts.len - 1, 1)
		a = pts[i-1]
		b = pts[i]
		d = segLen(a, b)
		if d <= 0 then continue
		s0 = s
		s = s + d
		lo = fromS
		if lo < s0 then lo = s0
		hi = toS
		if hi > s then hi = s
		if hi <= lo then continue
		if not out then out.push lerpPt(a, b, (lo - s0) / d)
		out.push lerpPt(a, b, (hi - s0) / d)
	end for
	if out.len < 2 then return null
	return out
end function

// Where a given distance along a polyline falls.
pointAt = function(pts, s)
	if pts == null or not pts then return null
	if s <= 0 then return [pts[0][0], pts[0][1]]
	acc = 0
	for i in range(1, pts.len - 1, 1)
		d = segLen(pts[i-1], pts[i])
		if d > 0 and acc + d >= s then
			return lerpPt(pts[i-1], pts[i], (s - acc) / d)
		end if
		acc = acc + d
	end for
	last = pts[pts.len - 1]
	return [last[0], last[1]]
end function
