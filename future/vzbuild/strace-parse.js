const tap = require('tap')
const p = require('panda-grammar')
const f = require('fs').readFileSync(process.argv[2], 'utf8').split('\n')

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
const openat = proj([2, 5, 8, 9, 10, 11], p.all(p.word, p.string('('), p.word, p.string(','), p.ws, cstring, p.string(','), p.ws, p.word,p.optional(p.many(p.all(p.string('|'),p.word))), p.optional(mode), 
	p.any
		( p.tag("complete", proj([4], p.all(p.string(')'), p.ws, p.string('='), p.ws, retVal)))
		, p.tag("unfinished", ignore(p.string(' <unfinished ...>')))
		)
))

const parse = proj([0, 2], p.all(
	nat,
	p.ws, 
	p.any
		( p.tag('openat', openat)
		, p.tag('exit', ignore(p.string('+++ exited with 0 +++')))
		, p.tag('resumed', proj([1, 3], p.all
			( p.string('<... ')
			, p.word
			, p.string(' resumed> )            = ')
			, retVal)))
		)
))

console.log(f[775])
console.log(parse(f[775]).value[1])

if (true)
{

	f.forEach((x, idx) => {
		const res = parse(x)
		if (res == null)
		{
			console.log(idx)
			console.log(x)
	//		console.log(res.value[2][5])
	//		console.log(res)
		}
	})
}
tap.plan(9)
tap.matchSnapshot
	( parse('13954 openat(AT_FDCWD, "/etc/ld.so.cache", O_RDONLY|O_CLOEXEC) = 3')
	, '001'
	)

tap.matchSnapshot
	( parse('14802 openat(AT_FDCWD, "/proc/self/mountinfo", O_RDONLY|O_LARGEFILE|O_CLOEXEC) = 3')
	, '002 - 3 flags'
	)

tap.matchSnapshot
	( parse('13954 openat(AT_FDCWD, "/usr/lib/tls/libtinfo.so.6", O_RDONLY|O_CLOEXEC) = -1 ENOENT (No such file or directory)')
	, '003 - ENOENT'
	)

tap.matchSnapshot
	( parse('13955 +++ exited with 0 +++13955 +++ exited with 0 +++')
	, '004 - exit'
	)

tap.matchSnapshot
	( parse('13954 openat(AT_FDCWD, "/usr/lib/gconv/gconv-modules.cache", O_RDONLY) = -1 ENOENT (No such file or directory)')
	, '005 - 1 flag'
	)

tap.matchSnapshot
	( parse('13954 openat(AT_FDCWD, "/dev/null", O_WRONLY|O_CREAT|O_TRUNC|O_LARGEFILE, 0666) = 3')
	, '006 - mode'
	)

tap.matchSnapshot
	( parse('13966 openat(AT_FDCWD, "/home/andy/dev/nano-pacstrap32/newroot/var/lib/pacman/db.lck", O_WRONLY|O_CREAT|O_EXCL|O_LARGEFILE|O_CLOEXEC, 000) = 4')
	, '007 - 000 mode'
	)

tap.matchSnapshot
	( parse('14005 openat(AT_FDCWD, "/proc/self/fd", O_RDONLY|O_LARGEFILE|O_DIRECTORY <unfinished ...>')
	, '008 - unfinished'
	)

tap.pass("should reach end of file")
/*
 
console.log(f.filter(x => x != '').map((x) => {
	const xx = x.match(pid)
	if (!xx)
	{
		console.log(x)
		process.exit(-1)
	}
	console.log(xx.input.slice(xx[0].length))
	process.exit()
	return xx ? xx.slice(1,10) : xx
}))
*/
