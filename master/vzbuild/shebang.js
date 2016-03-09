var fs = require('fs')

var she = '#'.codePointAt(0)
var bang = '!'.codePointAt(0)
var slash = '/'.codePointAt(0)
var lf = '\n'.codePointAt(0)
var space = ' '.codePointAt(0)

exports.check = function (fname)
{
	if (!fs.lstatSync(fname).isFile())
	{
		return null
	}
	var h = fs.openSync(fname, 0) 
	if (!h)
	{
		return null
	}
	var b = new Buffer(1024)
	b[0] = 0
	fs.readSync(h, b, 0, b.length)
	fs.closeSync(h)
	if (b[0] == she && b[1] == bang && b[2] == slash)
	{
		for (var i = 0; i < b.length; i++)
		{
			if (b[i] == space || b[i] == lf) break
		}
		
		return i < b.length ? b.slice(2, i).toString() : null
	}
	else
	{
		return null
	}
}
