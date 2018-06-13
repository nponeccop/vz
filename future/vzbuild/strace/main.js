const p = require('./parse')

p
	.parseFileSync(process.argv[2])
	.forEach(x => {
		const [pid, o] = x
		const [k] = Object.keys(o)

		const cb =
			{ 'openat': x =>
				{
					if ('ret' in x[5].complete)
					{
						console.log(x[1])
					}
				}
			, 'execve': x =>
				{
					if ('ret' in x[1].complete)
					{
						console.log(x[0])
					}
				}
			}

		if (k in cb)
		{
			cb[k](o[k])
		}
	})
