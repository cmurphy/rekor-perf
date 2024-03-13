#!/bin/bash

cat redis.dat mysql.dat > results.dat
entries=$(wc -l indices.csv | cut -d ' ' -f 1)
gnuplot -e "entries='$entries'" plot.gp

echo "Results output to graph.png."
