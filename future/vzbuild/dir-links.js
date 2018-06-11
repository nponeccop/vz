var fs = require('fs')
var path = require('path')
var assert = require('assert')

var shebang = require('./shebang')

assert.equal(process.argv.length, 4, "2 arguments are required")

var f = fs.readFileSync(process.argv[2], {encoding:'utf-8'}).split('\n')
f.pop()

var l = {}



var SRC = process.argv[3]

console.error({SRC})

function die(varargs)
{
	console.error.apply(null, arguments)
	process.exit(-1)
}


function resolve(src)
{
	if (!fs.existsSync(path.join(SRC, src)))
	{
		die("ERR3: Broken file list: %s doesn't exist", src)
	}

	var d = path.relative(SRC, path.join(SRC, src))
	var p = d.split('/').reduce(function (p, comp)
	{
		assert.notEqual(comp, '')
		var np = path.join(p, comp)
		var fullP = path.join(SRC, np)

		if (!fs.existsSync(fullP))
		{
			die("ERR1: Broken file list: %s doesn't exist", fullP)
		}

		if (fs.lstatSync(fullP).isSymbolicLink())
		{
			console.log(path.join('/', np))
			const ld = fs.readlinkSync(fullP)
			const rr = path.join('/', path.relative(SRC, path.resolve(SRC, p, ld)))
			resolve(rr)
			return rr
		}
		else
		{
			return np
		}
	}, '')


	const pp = path.join(SRC, p)
	if (!fs.existsSync(pp))
	{
		die("ERR2: Broken file list: %s doesn't exist", pp)
	}

	console.log(path.join('/', p))
	var sb = shebang.check(pp)
	if (sb != null)
	{
		resolve(sb)
	}
}

// resolve('/lib/libutil.so')

f.forEach(resolve)
//

