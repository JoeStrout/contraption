// syntaxCheck.ms -- compile every script on the disk, without running any of
// them, using the same MiniScript the game runs on.  Run it headless:
//
//	../MiniMicro2/raylib-miniscript tools/syntaxCheck.ms
//
// It opens no window.  Each file is compiled in a child interpreter
// (Interp.load compiles but does not run), so nothing needs Mini Micro's
// displays or the physics intrinsics to be set up first, and one file's
// errors cannot hide another's.  Exits 1 if anything failed to compile.

root = env.MS_SCRIPT_DIR + "/../disk"

scripts = []
gather = function(dir)
	for name in file.children(dir)
		path = dir + "/" + name
		if file.info(path).isDirectory then
			gather path
		else if name[-3:] == ".ms" then
			scripts.push path
		end if
	end for
end function
gather root

failed = 0
p = Interp.create
for path in scripts
	p.load file.readLines(path).join(char(10)), path
	if p.error then
		print path[root.len + 1:] + ": " + p.error
		failed += 1
	end if
end for
p.dispose

print scripts.len + " scripts checked, " + failed + " with errors"
if failed then exit 1
