default:
	echo "-define(VERSION,\"`git rev-parse HEAD | head -c 6`\")." > include/vox.hrl
	mad cle dep com bun vox
