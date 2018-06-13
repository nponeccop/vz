const p = require('panda-grammar')

const re = (x) => p.re(x)
const nat = re(/^\d+/)
const neg = re(/^-\d+/)
const name = re(/^\d+/)
const cstring = p.re(/^".*?"/)
const proj = (nums, matcher) => p.rule(matcher, x => nums.length == 1
	? x.value[nums[0]]
	: nums.map(idx => x.value[idx]))
const ignore = x => p.rule(x, _ => null)
const mode = p.re(/^, (0\d{3}|000)/)

const retVal = p.any
	( p.tag("ret", nat)
	, p.tag("err", proj([0,2,4], p.all(neg, p.ws, p.word, p.ws, p.re(/\(.*?\)/))))
	)
const completion = p.any
	( p.tag("complete", proj([4], p.all(p.string(')'), p.ws, p.string('='), p.ws, retVal)))
	, p.tag("unfinished", ignore(p.string(' <unfinished ...>')))
	)
const openat = proj([2, 5, 8, 9, 10, 11], p.all(p.string('openat'), p.string('('), p.word, p.string(','), p.ws, cstring, p.string(','), p.ws, p.word,p.optional(p.many(p.all(p.string('|'),p.word))), p.optional(mode), completion))

const execve = proj([1, 3], p.all(p.string("execve("), cstring, re(/.*? vars \*\//), completion))

exports.parse2 = proj([0, 2], p.all(
	nat,
	p.ws, 
	p.any
		( p.tag('openat', openat)
		, p.tag('execve', execve)
		, p.tag('signal', ignore(re(/^--- SIG\w+ {.*} ---$/)))
		, p.tag('exit', ignore(p.string('+++ exited with 0 +++')))
		, p.tag('resumed', proj([1, 3], p.all
			( p.string('<... ')
			, p.word
			, p.string(' resumed> )            = ')
			, retVal)))
		)
))

exports.parse = p.grammar(exports.parse2)

