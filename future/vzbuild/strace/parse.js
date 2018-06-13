const grammar = require('./grammar')


const parse2 = grammar.parse2

if (false)
{
	const f = require('fs').readFileSync(process.argv[2], 'utf8').split('\n')
	const idx = 318
	console.log(f[idx])
	const r = parse2(f[idx])
	console.log(r == null ? r : r.rest == '' ? r.value[1] : { value: r.value[1].execve, rest: r.rest})
	f.forEach((x, idx) => {
		const res = parse2(x)
		if (res == null)
		{
			console.log(idx)
			console.log(x)
	//		console.log(res.value[2][5])
	//		console.log(res)
		}
	})
}

