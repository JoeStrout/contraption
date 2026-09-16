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
