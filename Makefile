build:
	TTREERC=.ttreerc ttree -a

local:
	TTREERC=.ttreerc ttree -a --define base=$(shell pwd)/
