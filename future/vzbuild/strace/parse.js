const fs = require('fs')
const grammar = require('./grammar')

exports.parseFileSync = fileName => exports.parseArray(
	fs
		.readFileSync(fileName, 'utf8')
		.split('\n')
		.filter(x => x != '')
)

exports.parseArray = lineArray => {

	const unfinished = {}

	const mapFn = (x) => {
		const [pid, o] = grammar.parse(x)
		const suspend = (co) =>
		{
			const [kk] = Object.keys(co)
			if (kk == 'unfinished')
			{
				if (pid in unfinished)
				{
					throw new Error("double unfinished!")
				}
				unfinished[pid] = o
				return true
			}
			else
			{
				return false
			}
		}

		const [k] = Object.keys(o)
		const v = o[k]

		switch (k)
		{
		case 'execve':
			const [path, co] = v
			suspend(co)
			break;
		case 'openat':
			{
				const co = v[5]
				if (suspend(co))
				{
					return null
				}
			}
		case 'exit':
		case 'signal':
			break;
		case 'resumed':
			const [call, ret] = v

			if (('unfinished' in ret)) {
				throw new Error('unfinished resume!')
			}
			const oo = unfinished[pid]
	//		console.log(oo)
			const [kkk] = Object.keys(oo)
			switch (kkk) {
			case 'execve':
				oo.execve[1] = ret
				return [pid, oo]
			case 'openat':
				oo.openat[5] = ret
				return [pid, oo]
			}

			break;
		default:
			console.log(o)
			process.exit()
		}
		return [pid, o]
	}

	return lineArray
	.map(mapFn)
	.filter(x => x != null)
}
