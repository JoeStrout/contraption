// Main menu for the Contraption game.
//
// This is a text-based stand-in; we'll do a fancy graphical
// menu later.
//
// It hands over to contraption.ms by way of two globals, which `run` keeps:
// puzzleName (the file's name without ".json") and puzzlePlaying (true to
// play it, false to edit it -- the same switch as contraption's setUpPuzzle).

clear
import "importUtil"
ensureImport ["config"]
import "textUtil"
import "chars"
import "stringUtil"

textUtil.printCenteredAt 34,22, "CONTRAPTION"

while true
	text.row = 18
	print "    [E]dit Puzzle"
	print "    [P]lay Puzzle"
	print
	print "===> " + chars.inverseOn + " " + chars.inverseOff, ""
	textUtil.clearToEOL
	k = key.get.upper
	print char(8) + k
	if k == char(27) then exit
	if k == "E" or k == "P" then break
end while
globals.puzzlePlaying = (k == "P")

nextNum = 1
options = {}
names = file.children(config.puzzle.dir)
if names == null then names = []    // no puzzles folder yet: nothing saved
for fname in names
	if not fname.endsWith(".json") then continue
	print " " * (nextNum < 10) + nextNum + ". " + (fname - ".json")
	options[nextNum] = fname
	nextNum += 1
end for
if not puzzlePlaying then print " N. New Puzzle"
print
verb = "edit"
if puzzlePlaying then verb = "play"
while true
	choice = input("Select puzzle to " + verb + ": ")
	if not puzzlePlaying and choice.upper == "N" then
		filename = input("Enter new filename: ").trim
		if filename == "" or filename == ".json" then continue
		if not filename.endsWith(".json") then filename += ".json"
		break
	end if
	choice = choice.val
	if options.hasIndex(choice) then
		filename = options[choice]
		break
	end if
end while

print "Loading: " + filename
wait 0.5

globals.puzzleName = filename - ".json"
run "contraption"
