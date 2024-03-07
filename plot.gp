#!/usr/bin/gnuplot

set term png
set output "graph.png"

set style line 1 lc rgb "#40a7db"
set style line 2 lc rgb "#b38df0"
set yrange [0:]
set style fill solid
set boxwidth 0.5
set ylabel "Latency (nanoseconds)"
set format y '%.0f'
set bmargin 6
set grid y

plot "results.dat" every ::0::1 using 1:3:xtic(2) with boxes linestyle 1 notitle, \
    "results.dat" every ::0::1 using 1:($3+200000):(sprintf('%3.2f', $3)) with labels notitle, \
    "results.dat" every ::2::3 using 1:3:xtic(2) with boxes linestyle 2 notitle, \
    "results.dat" every ::2::3 using 1:($3+200000):(sprintf('%3.2f', $3)) with labels notitle
