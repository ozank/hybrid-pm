
#Get Best results
pop <- read.table('genoud3.pro', comment.char = 'G') 
best <- pop[pop$V1 == 1,, drop = FALSE] 
very.best <- as.matrix(best[nrow(best), 3:ncol(best)]) 

pop_size=50
max_generation=33

#Plot Optimization Data
plot(best$V2, type="b", ylab="Cost Function", xlab="Generation", main="Cost(best) vs Generation")

#Plot all points
points(rep(seq(1:max_generation),each=pop_size),pop$V2)