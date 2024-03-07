#!/bin/bash

cat redis.dat mysql.dat > results.dat
./plot.gp

echo "Results output to graph.png."
