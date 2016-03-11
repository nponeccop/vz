var fs = require('fs')
var path = require('path')
var f = fs.readFileSync(process.argv[2], {encoding:'utf-8'}).split('\n')
var assert = require('assert')
var shebang = require('./shebang')
f.pop()

var l = {}

var SRC = '/'

function resolve(src)
{
	var d = path.relative(SRC, src)
	var p = path.resolve(SRC, d.split('/').reduce(function (p, comp)
	{
		assert.notEqual(comp, '')
		var np = p + '/' + comp

		if (fs.existsSync(np) && fs.lstatSync(np).isSymbolicLink())
		{
			console.log(np)
			return path.resolve(SRC, p, fs.readlinkSync(np))
		}
		else
		{
			return np
		}
	}, ''))
	if (fs.existsSync(p))
	{
		console.log(p)
		var sb = shebang.check(p)
		if (sb != null)
		{
			resolve(sb)
		}
	}
}

f.forEach(resolve)
