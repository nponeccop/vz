var fs = require('fs')
var path = require('path')
var f = fs.readFileSync(process.argv[2], {encoding:'utf-8'}).split('\n')

f.pop()

var l = {}

var SRC = '/'

f.forEach(function (src)
{
	var p = ''
	path.dirname(src).split('/').forEach(function (comp)
	{
		var np = p + '/' + comp

		if (fs.lstatSync(SRC + np).isSymbolicLink())
		{
			var rp = fs.readlinkSync(SRC + np)
			if (! (np in l))
			{
				l[np] = rp
				var relRp = path.relative(SRC + p, SRC + np)
				console.log('mkdir -p $DST/%s\ncd $DST/%s\nln -s %s %s', rp, p, rp, relRp)
			}
			p = rp
		}
		else
		{
			p = np		
		}
	})

//	p += '/' + path.basename(src)
//	console.log('install %s', p)
})
