#script to calculate changes in Denny wood ground flora over time#
rm(list=ls(all=TRUE))

#open packages neeeded
library(ggplot2)
library(plyr)
library(ape)
library(geoR)
library(vegan)
library(reshape2)
library(lme4)
library(MuMIn)
library(gridExtra)


#load in data
BA<-read.csv("Data/Denny_plots.csv")
GF<-read.csv("Data/GF_ab_nw.csv")
Grass<-read.csv("Data/Reclass_grass.csv")

#replace na with zeros in dataframe
GF[is.na(GF)] <- 0

#remove data from plots 26, 44 and 45 which have incomplete records
GF<-subset(GF,Block!=26)
GF<-subset(GF,Block!=44)
GF<-subset(GF,Block!=45)
GF[GF==2001]<-1999

#produce counts of species per block per year
GF_melt<-melt(GF,id =c("Block","Year") )
head(GF_melt)
#remove rows with NAs
GF_melt2<-GF_melt[complete.cases(GF_melt),]

#and species richness
GF_melt3<-subset(GF_melt2,value>0)
GF_Sp_R<-count(GF_melt3,vars = c("Block","Year"))

#####################################################
# ground flora abundance#############################
#####################################################

#remove the sum of all ground cover
GF_melt2<-subset(GF_melt2,variable!="Ground_cover")

#remove space from species names for Grass table
Grass$Species<-gsub(" ", "", Grass$Species, fixed = TRUE)
Grass$Species<-as.factor(Grass$Species)
Grass$Species2<-as.numeric(Grass$Species)


GF_melt2$variable<- factor(GF_melt2$variable, levels=levels(Grass$Species))
GF_melt2$variable2<-as.numeric(GF_melt2$variable)

#add column to identify species as grass - this needs fixing
GF_melt2$Grass<-"No"
for (i in 1:nrow(Grass)){
  for (y in 1:nrow(GF_melt2)){
    GF_melt2$Grass[y]<-ifelse(GF_melt2$variable[y]==Grass$Species[i],as.character(Grass$FF[i]),as.character(GF_melt2$Grass[y]))
  }
}

GF_melt2$Grass<-as.factor(GF_melt2$Grass)

#subset to only include grass species
Grass_species<-subset(GF_melt2,Grass=="Grass")
#sum the cover of grassy species
Grass_cover<-aggregate(Grass_species$value, list(Grass_species$Block,Grass_species$Year), sum)
colnames(Grass_cover)<-c("Block","Year","Perc_C")

#calculate changes in grass abundance relative to first survey
#do this using a loop and calculating the raw percentage difference
head(Grass_cover)
Grass_cover<-Grass_cover[with(Grass_cover, order(Year)), ]

Blocks<-unique(Grass_cover$Block)
Rel_Ab<-NULL
for (i in 1:length(Blocks)){
Cov_block<-subset(Grass_cover,Block==Blocks[i])  
Cov_block$PCC<-Cov_block$Perc_C-Cov_block$Perc_C[1]
Rel_Ab<-rbind(Rel_Ab,Cov_block)
}

#merge data on abundances to data on BA change
head(BA)
BA2<-subset(BA,select=c("Year","Block","BAPERCM","BAM"))
BA_ab<-merge(Rel_Ab,BA2,by=c("Block","Year"))
write.csv(BA_ab,"Data/Grass_ab_BA.csv",row.names=F)


############################################################
#analysis of change in grass abundance######################
############################################################
BA_ab<-read.csv("Data/Grass_ab_BA.csv")
BA_ab<-subset(BA_ab,Year>1964)

BA_ab$Perc_C2<-(BA_ab$Perc_C/100)
BA_ab$Perc_C2<-ifelse(BA_ab$Perc_C2>1,BA_ab$Perc_C2-0.02,BA_ab$Perc_C2+0.01)
BA_ab$BAPERCM2<-BA_ab$BAPERCM*-1

ggplot(BA_ab,aes(x=BAPERCM2,y=Perc_C2))+geom_point()+facet_wrap(~Year)+geom_smooth()

#null model
M0.1_G<-lmer(qlogis(Perc_C2)~1+(1|Block),data=BA_ab)
M0.2_G<-lmer(qlogis(Perc_C2)~1+(1|Block)+(1|Year),data=BA_ab)
M0.3_G<-lmer(qlogis(Perc_C2)~1+(1|Block)+(BAPERCM2|Year),data=BA_ab)
M0.4_G<-lmer(qlogis(Perc_C2)~1+(BAPERCM2|Year),data=BA_ab)
M0.5_G<-lmer(qlogis(Perc_C2)~1+(1|Year),data=BA_ab)

AICc(M0.1_G,M0.2_G,M0.3_G,M0.4_G,M0.5_G)

dotplot(ranef(M0.1_G,condVar=TRUE),
        lattice.options=list(layout=c(1,2)))

#fixed effects models
M1_G<-lmer(qlogis(Perc_C2)~BAPERCM2+(BAPERCM2|Year),data=BA_ab)
M2_G<-lmer(qlogis(Perc_C2)~BAPERCM2+I(BAPERCM2^2)+(BAPERCM2|Year),data=BA_ab)
M3_G<-lmer(qlogis(Perc_C2)~BAPERCM2+I(BAPERCM2^2)+I(BAPERCM2^3)+(BAPERCM2|Year),data=BA_ab)

plot(M3_G)
qqnorm(resid(M3_G))

summary(M3_G)


Grass_models<-list(M1_G,M2_G,M3_G,M0.4_G)

#produce model selection table
Grass_sel<-model.sel(Grass_models,REML=F,fit=T)
Grass_sel$R_sq<-c(r.squaredGLMM(M3_G)[1],r.squaredGLMM(M2_G)[1],r.squaredGLMM(M1_G)[1],r.squaredGLMM(M0.4_G)[1])
write.csv(Grass_sel,"Figures/Mod_sel_Grass_grad.csv")

#now get model averaged variables
Grass_avg<-model.avg(Grass_sel,fit=T,subset=delta<7)
summary(Grass_avg)
importance(Grass_avg)
terms(Grass_sel)
Grass_avg2<-summary(Grass_avg)  


BA_ab$Pred<-predict(Grass_avg,re.form=NA)

plogis(BA_ab$Pred)

#now create plots of this
newdat<-expand.grid(BAPERCM2=seq(min(BA_ab$BAPERCM2),max(BA_ab$BAPERCM2),0.01))
newdat$Perc_C2<-0

mm <- model.matrix(terms(M3_G),newdat)
newdat$Perc_C2 <- predict(Grass_avg,newdat,re.form=NA)
pvar1 <- diag(mm %*% tcrossprod(vcov(M3_G),mm))
tvar1 <- pvar1+VarCorr(M3_G)$Year[1]  ## must be adapted for more complex models
  newdat <- data.frame(
    newdat
    , plo = newdat$Perc_C2-2*sqrt(pvar1)
    , phi = newdat$Perc_C2+2*sqrt(pvar1)
    , tlo = newdat$Perc_C2-2*sqrt(tvar1)
    , thi = newdat$Perc_C2+2*sqrt(tvar1)
  )


#plot this relationship
theme_set(theme_bw(base_size=12))
Grass_plot1<-ggplot(BA_ab,aes(x=BAPERCM2*100,y=Perc_C,colour=as.factor(Year)))+geom_point(shape=1,size=3)
Grass_plot2<-Grass_plot1+theme(panel.grid.major = element_blank(),panel.grid.minor = element_blank(),panel.border = element_rect(size=1.5,colour="black",fill=NA))
Grass_plot3<-Grass_plot2+geom_ribbon(data=newdat,aes(x=BAPERCM2*100,ymax=plogis(phi)*100,ymin=plogis(plo)*100,y=plogis(Perc_C2)*100),alpha=0.2,colour=NA)
Grass_plot4<-Grass_plot3+geom_line(data=newdat,aes(x=BAPERCM2*100,y=plogis(Perc_C2)*100),colour="black",alpha=0.8)+ylab("Subplot grass cover (%)")+xlab("Percentage loss of basal area since 1964")
Grass_plot5<-Grass_plot4+scale_colour_brewer("Year",palette ="Set1")+xlim(-50,100)+theme(legend.position="none")
Grass_plot5
ggsave("Figures/Grass_cover_gradient.png",width = 8,height=6,units = "in",dpi=300)

#plot of this relationsip for ICCB poster
theme_set(theme_grey(base_size=30))
Grass_plot1<-ggplot(BA_ab,aes(x=BAPERCM2*100,y=Perc_C,colour=as.factor(Year)))+geom_point(alpha=0.5,size=4)
Grass_plot2<-Grass_plot1
Grass_plot3<-Grass_plot2+geom_ribbon(data=newdat,aes(x=BAPERCM2*100,ymax=plogis(phi)*100,ymin=plogis(plo)*100,y=plogis(Perc_C2)*100),alpha=0.2,colour=NA)
Grass_plot4<-Grass_plot3+geom_line(data=newdat,aes(x=BAPERCM2*100,y=plogis(Perc_C2)*100),colour="black",alpha=0.8)+ylab("Subplot grass cover (%)")+xlab("Percentage loss of \nbasal area since 1964")
Grass_plot5<-Grass_plot4+scale_colour_brewer("Year",palette ="Set1")+xlim(-50,100)
Grass_plot5
ggsave("Figures/Grass_cover_gradient_ICCB.jpeg",width = 29,height=29,units = "cm",dpi=800)


#######################################################
#analysis of bracken cover#############################
#######################################################

Bracken<-subset(GF_melt2,variable=="Pteridium.aquilinum")

#calculate changes in bracken abundance relative to first survey
#do this using a loop and calculating the raw percentage difference
head(Bracken)
Bracken<-Bracken[with(Bracken, order(Year)), ]

Blocks<-unique(Bracken$Block)
Rel_Ab<-NULL
for (i in 1:length(Blocks)){
  Cov_block<-subset(Bracken,Block==Blocks[i])  
  Cov_block$PCC<-Cov_block$value-Cov_block$value[1]
  Rel_Ab<-rbind(Rel_Ab,Cov_block)
}

#merge data on abundances to data on BA change
BA2<-subset(BA,select=c("Year","Block","BAPERCM","BAM"))
BA_ab<-merge(Rel_Ab,BA2,by=c("Block","Year"))
Brack_Ab<-BA_ab
#remove data from 1964
Brack_Ab<-subset(Brack_Ab,Year>1964)

theme_set(theme_bw(base_size=12))
Brack_plot1<-ggplot(Brack_Ab,aes(x=BAPERCM*100*(-1),y=value,colour=as.factor(Year)))+geom_point(shape=1,size=3)
Brack_plot2<-Brack_plot1+theme(panel.grid.major = element_blank(),panel.grid.minor = element_blank(),panel.border = element_rect(size=1.5,colour="black",fill=NA))
Brack_plot2+scale_colour_brewer("Year",palette ="Set1")+ylab("Percentage cover of bracken")+xlab("Percentage loss of basal area since 1964")
ggsave("Figure/Bracken_cover_gradient.png",width = 8,height=6,units = "in",dpi=300)



#models of this
#first fix percentage value
Brack_Ab$value<-Brack_Ab$value/100
Brack_Ab$value2<-ifelse(Brack_Ab$value==1,Brack_Ab$value-0.01,Brack_Ab$value)
Brack_Ab$value2<-ifelse(Brack_Ab$value==0,Brack_Ab$value+0.01,Brack_Ab$value2)
Brack_Ab$value2_trans<-qlogis(Brack_Ab$value2)

#models of this
M0<-lmer(value2~1+(1|Block),data=Brack_Ab)
M1<-lmer(value2~BAPERCM+(1|Block),data=Brack_Ab)
M2<-lmer(value2~BAPERCM+I(BAPERCM^2)+(1|Block),data=Brack_Ab)
M3<-lmer(value2~BAPERCM+I(BAPERCM^2)+I(BAPERCM^3)+(1|Block),data=Brack_Ab)
AICc(M0,M1,M2,M3)
mod_list<-list(M0,M1,M2,M3)

Mod_sel_brack<-model.sel(mod_list)
Mod_sel_brack$R_2<-c(r.squaredGLMM(M0)[1],r.squaredGLMM(M1)[1],r.squaredGLMM(M3)[1],
                    r.squaredGLMM(M2)[1])
Mod.avg_brack<-model.avg(Mod_sel_brack,subset= delta <7)
summary(Mod.avg_brack)


write.csv(Mod_sel_brack,"Figures/Mod_sel_brack.csv")
######################################################
#ground flora species richness########################
######################################################

#plot this over time
ggplot(GF_Sp_R,aes(x=Year,y=freq,group=Block))+geom_line()+facet_wrap(~Block)

#do a comparison of species richness in 1964 to that now
head(GF_Sp_R)


Block_SpR<-unique(GF_Sp_R$Block)
Rel_SpR<-NULL
for (i in 1:length(Block_SpR)){
  SpR_block<-subset(GF_Sp_R,Block==Block_SpR[i])  
  SpR_block$PSpR<-log(SpR_block$freq)-log(SpR_block$freq[1])
  Rel_SpR<-rbind(Rel_SpR,SpR_block)
}



#merge species richness data to plot data
GF_Sp_BA<-merge(Rel_SpR,BA,by=c("Block","Year"))
str(GF_Sp_BA)
GF_Sp_BA$BAPERCM2<-GF_Sp_BA$BAPERCM*(-1)
GF_Sp_BA<-subset(GF_Sp_BA,Year>1964)
GF_Sp_BA$Year2<-(GF_Sp_BA$Year-mean(GF_Sp_BA$Year))/sd(GF_Sp_BA$Year)


head(GF_Sp_BA)


#plot of relationship between species richness against collapse gradient
#null model
Rich_M0.1<-glmer(freq~1+(1|Block),data=GF_Sp_BA,family=poisson)

dotplot(ranef(Rich_M0.1,condVar=TRUE),
        lattice.options=list(layout=c(1,2)))

#linear relationship - this is really the only logical relationship I can think of
Rich_M1<-glmer(freq~BAPERCM2+(1|Block),data=GF_Sp_BA,family=poisson)
Rich_M2<-glmer(freq~BAPERCM2+I(BAPERCM2^2)+(1|Block),data=GF_Sp_BA,family=poisson)


AICc(Rich_M0.1,Rich_M1,Rich_M2)
Rich_models<-list(Rich_M1,Rich_M2,Rich_M0.1)

Rich_sel<-model.sel(Rich_models,REML=F)
Rich_sel$R_sq<-c(r.squaredGLMM(Rich_M2)[1],r.squaredGLMM(Rich_M1)[1],r.squaredGLMM(Rich_M0.1)[1])
Rich_avg<-model.avg(Rich_sel,subset=delta<7)
summary(Rich_avg)
write.csv(Rich_sel,"Figures/Mod_sel_Spr_GF.csv")

#now create plots of this
newdat_grass<-data.frame(BAPERCM2=seq(min(GF_Sp_BA$BAPERCM2),max(GF_Sp_BA$BAPERCM2),0.01))
newdat_grass$freq<-0

mm <- model.matrix(terms(Rich_M2),newdat_grass)
newdat_grass$freq <- predict(Rich_avg,newdat_grass,re.form=NA)
pvar1 <- diag(mm %*% tcrossprod(vcov(Rich_M2),mm))
tvar1 <- pvar1+VarCorr(Rich_M2)$Block[1]  ## must be adapted for more complex models
newdat_grass <- data.frame(
  newdat_grass
  , plo = newdat_grass$freq-2*sqrt(pvar1)
  , phi = newdat_grass$freq+2*sqrt(pvar1)
  , tlo = newdat_grass$freq-2*sqrt(tvar1)
  , thi = newdat_grass$freq+2*sqrt(tvar1)
)



#plot richness against BA
theme_set(theme_bw(base_size=12))
ggplot(GF_Sp_BA,aes(x=BAM,y=freq))+geom_point(shape=1,size=3,aes(colour=as.factor(Year)))

Rich_BA<-ggplot(GF_Sp_BA,aes(x=BAPERCM2*100,y=freq))+geom_point(shape=1,size=3,aes(colour=as.factor(Year)))
Rich_BA2<-Rich_BA+theme(panel.grid.major = element_blank(),panel.grid.minor = element_blank())+ylab("Subplot ground flora species richness")+xlab("Percentage loss of basal area since 1964")
Rich_BA3<-Rich_BA2+geom_ribbon(data=newdat_grass,aes(ymax=exp(phi),ymin=exp(plo),group=NULL,shape=NULL),alpha=0.2)+geom_line(data=newdat_grass,aes(x=BAPERCM2*100,y=exp(freq)))+scale_colour_brewer(name="Year",palette ="Set1")
Rich_BA3+theme(legend.position="none")+theme(panel.grid.major = element_blank(),panel.grid.minor = element_blank(),panel.border = element_rect(size=1.5,colour="black",fill=NA))
ggsave("Figures/GF_SPR.png",width = 8,height=6,units = "in",dpi=300)

#create plot combining grass cover and species richness plots 
Grass_plot6<-Grass_plot5+theme(legend.position="none")+annotate("text",x=-50,y=100,label="(a)")
Rich_BA4<-Rich_BA3+theme(legend.position="none")+annotate("text",x=-50,y=20,label="(b)")+theme(panel.grid.major = element_blank(),panel.grid.minor = element_blank(),panel.border = element_rect(size=1.5,colour="black",fill=NA))

png("Figures/Grass_cov_richness.png",width = 10,height = 6,units = "in",res = 600)
grid.arrange( Grass_plot6, Rich_BA4, ncol=2)
dev.off()



#############################################################
#Community similarity for ground flora#######################
#############################################################

Blocks<-unique(GF$Block)
drops<-c("Ground_cover")
GF<-GF[,!(names(GF) %in% drops)]
Sor_similarity<-NULL
for (i in 1:length(Blocks)){
  print(i)
  Block_subset<-subset(GF,Block==Blocks[i])
  Block_subset<-Block_subset[with(Block_subset, order(Year)), ]
  Block_subset[is.na(Block_subset)]<-0
  Block_subset2<-Block_subset[-c(1:2)]
  Block_subset$Sorensen<-c(1,1-vegdist(Block_subset2)[1:nrow(Block_subset2)-1])
  Sor_similarity<-rbind(Sor_similarity,Block_subset)
}
Sor_similarity2<-subset(Sor_similarity,Year>1964)

str(Sor_similarity2)

#merge community composition data to plot data
BA3<-subset(BA,select=c(BAPERCM,Year,Block))
GF_BA_2<-merge(BA,Sor_similarity2,by=c("Block","Year"))
GF_BA_3<-subset(GF_BA_2, select=c(BAM,BAPERCM,Sorensen,Year,Block))
ggplot(GF_BA_3,aes(x=BAPERCM,y=Sorensen,group=Block,colour=as.factor(Year)))+geom_point()


#these plots seem to show a reduction in similarity with increasing basal area loss, but let's do this properly
#with statistics!
GF_BA_3$Sor2<-GF_BA_3$Sorensen+0.01

#first a null model
M0.1<-lmer(qlogis(Sor2)~1+(1|Block),data=GF_BA_3)
M0.2<-lmer(qlogis(Sor2)~1+(Block|Year),data=GF_BA_3)
AICc(M0.1,M0.2)
plot(M0.1)
plot(M0.2)

#we go with formation of M0.2 becuase AICc is lowest
#now add fixed terms
M1<-lmer(qlogis(Sor2)~BAPERCM+(1|Block),data=GF_BA_3)
M2<-lmer(qlogis(Sor2)~BAPERCM+I(BAPERCM^2)+(1|Block),data=GF_BA_3)
M3<-lmer(qlogis(Sor2)~BAPERCM+I(BAPERCM^2)+I(BAPERCM^3)+(1|Block),data=GF_BA_3)
plot(M1)#seems a bit shit, need to work out box cox transformation for this

#plot this non-relationship
GF_sor1<-ggplot(GF_BA_3,aes(x=BAPERCM*100,y=Sorensen,group=Block,colour=as.factor(Year)))+geom_point(size=3,shape=1)
GF_sor2<-GF_sor1+theme(panel.grid.major = element_blank(),panel.grid.minor = element_blank())+ylab("Sorenson similarity to community present in 1964")+xlab("Percentage change in basal area since 1964")
GF_sor2+scale_colour_discrete(name="Year of measurements")
setwd("C:/Users/Phil/Dropbox/Work/Active projects/Forest collapse/Denny_collapse/Figures")
ggsave("GF_Sorenson.png",width = 8,height=6,units = "in",dpi=300)



