var fs = require('fs')
var path = require('path')
var f = fs.readFileSync(process.argv[2], {encoding:'utf-8'}).split('\n')
var assert = require('assert')
f.pop()

var l = {}

var SRC = '/'

f.forEach(function (src)
{
	var d = path.relative(SRC, src)
	console.log(path.resolve(SRC, d.split('/').reduce(function (p, comp)
	{
		assert.notEqual(comp, '')
		var np = p + '/' + comp

		if (fs.lstatSync(np).isSymbolicLink())
		{
			console.log(np)
			return path.resolve(SRC, p, fs.readlinkSync(np))
		}
		else
		{
			return np
		}
	}, '')))
})
