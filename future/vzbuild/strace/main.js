const p = require('./parse')

p
	.parseFileSync(process.argv[2])
	.forEach(x => console.log(x))
