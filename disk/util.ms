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
