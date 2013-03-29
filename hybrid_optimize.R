#INITILIZATION & FUNCTION DEFINITION

#Define the constant dimensions for the hybrid machine

filename <- "/var/tmp/hybrid_pm_03_06/2012_06_03_hybrid_pm"
R_out <- 112
hs <- 30
ac <- 2
R_in <- R_out-hs-ac
w <- 3
N_sym <- 12
alfa_sym <-360/N_sym

constants <- c(R_out,hs,ac,R_in,w,N_sym,alfa_sym)
  
#Write constant dimensions to comi file
write(rbind(c("$STRING filename","$CONS #R_out","$CONS #hs","$CONS #ac","$CONS #R_in","$CONS #w",
              "$CONS #N_sym","$CONS #alfa_sym"), 
            c(filename,constants)), 
      file="dimensions_hybrid_pm_constant.comi",ncolumns=2,sep="\t")


#variables<-c(1,0.65,12,0.8,0.95,20,30,8,0.4)
variables<-c(0.92,0.44,11.35,0.856,0.888,34.4,15.7,13.98,0.4734)

#Define Coil Matrix (can be modified, distributed winding)
Nslot<-90
slot_angle<-360/Nslot
Nslotpp<-Nslot/3/(N_sym)*4 #Number od slots per pole per phase

coil_matrix<-matrix(0,120,1)  #create zero matrix

for (i in 1:(Nslotpp/2))
{
  first<-i*slot_angle             #Start position of the coil
  end<-i*slot_angle+360/N_sym-1  #End position of the coil(-1 for correction)
  
  coil_matrix[first:end]<-coil_matrix[first:end]+1/(Nslotpp/2)      #increase the coil value by a step
}


#  Cost Calculation -------------------------------------------------------

cost <- function (variables)
{
  geometry_penalty<-constraint_check(variables,constants)
  
  if(geometry_penalty==0) #If no errors in geometry, get the FEA results
  {
    #modify the function inputs
    flux <- get_flux(variables,constants)
    
    V_max<-max_voltage(flux,coil_matrix)
  }
  else
  {
    V_max<-0
  }
    
  #Minimum limit for induced voltage
  V_limit<-32
  #Penalty function for Voltage
    if(V_max>=V_limit)
    {
      V_penalty<-0
    }
    else
    {
      #approaches to zero as voltage approaches V_limit
      V_penalty<-(V_limit-V_max)^2
    }
    
  #Calculate Magnet price
    neo_price<-75 #Neomidium in £/kg
    sam_price<-15 #Samarium in £/kg
    
    #NdFeB area Rin*sin(alfa)*h_neo+0.5*Rin^2(alfa(radians)-sin(alfa)cos(alfa))
    area_neo<- constants[4]*sin(constants[7]*variables[2]*pi/180)*variables[3]+
              0.5*constants[4]^2*(constants[7]*variables[2]*pi/180-sin(constants[7]*variables[2]*pi/180)*cos(constants[7]*variables[2]*pi/180))
    
    magnet_cost<-sam_price*variables[7]*variables[8]*constants[5]*8.4e-6 +
                neo_price*area_neo*constants[5]*7.4e-6
        #Sam_price * L_sam * W_sam * W *density(kg/mm3)
        #Neo_price *area_neo*w*density(kg/mm3)
        #100 for the axial length of the machine
    
    #Total cost
    total_cost<-geometry_penalty+V_penalty+magnet_cost
    
    return(total_cost)
}


# Opera Simulations -------------------------------------------------------

get_flux<-function(xx,constants)
{
  #Update dimensions and write to comi file
  #Define variable names
  names<-c("$CONS #k_radius_neo",
           "$CONS #k_angle_neo",
           "$CONS #h_neo",
           "$CONS #k_radius_sam",
           "$CONS #k_angle_sam",
           "$CONS #rotation_sam",
           "$CONS #L_sam",
           "$CONS #W_sam",
           "$CONS #k_extra_air")
  
  #Make k_radius_neo=1
  xx[1]<-1
  
  #Write data to comi file
  write(rbind(names,xx), file="dimensions_hybrid_pm_variable.comi",ncolumns=2,sep="\t")
  
  #Run the Opera simulation (Linux)
  #If there's an error it will be written to error_check variable
  error_check<-system("~/Applications/Opera_15/bin/modeller Create_hybrid_pm.comi -nodisplay", wait=TRUE, intern=TRUE)
  
  if(any(grepl("error", error_check, ignore.case=TRUE)))
  {
    #An error occured (probably in meshing)
    #assign zero matrix to Bcomp
    B_comp<-matrix(0,120,2)
  }
  else
  {
  #Import post process table
  #first column angle
  #second - B_radial
  B_rad <- as.matrix(read.table("airgap_flux.table", quote="\"", skip=4))
  
  #complete cycle (concave four matrices)
  #first column is mechanical angle in degrees (starts from 1)
  B_comp<- cbind(-59:60, c(-B_rad[-1,2],B_rad[30:2,2],B_rad[,2],-B_rad[30:1,2]))
  }
  
  return(B_comp)
  #plot(B_comp, type="l")
}


# Voltage Magnitude -------------------------------------------------------

max_voltage<-function(B_com,coil_matrix)
{
  #Rotation Loop    
  Total_flux<-matrix(0,120,1)
  for (i in 0:120)
  {
    coil_matrix<-c(coil_matrix[-1],coil_matrix[1])      #Circular rotation for coil matrix, move one slot pitch each time
    #Total Flux (multiply flux density with coil matrix) #!doesn't give the real voltage value
    Total_flux[i]<-sum(B_com[,2]*coil_matrix)  
  }
  
  #Sinusoidal Curve fitting
  sinusoidal_curve<-nls(Total_flux~a*cos(((1:120)+b)*pi/60),start=list(a=-10,b=-40)) 
  #Curve fitting as the shape of A*sin(wt+theta)
    #plot(Total_flux,type="l")
    #lines(coef(sinusoidal_curve)[1]*cos(((1:120)+coef(sinusoidal_curve)[2])*pi/60),col="red")
    #grid()
  #Get coefficient of the sinusoidal approx.
  #abs(coef(sinusoidal_curve)[1])
  
  return(max(fitted.values(sinusoidal_curve)))

}

# Constraint Check --------------------------------------------------------

#Function returns true if all constraints are satisfied
constraint_check <- function (variables, constants)
{
  #Coordinates of Point A of Samarium Magnet
  beta<-variables[5]*constants[7]*pi/180  # k_angle_sam * alfa_sym in radians
  gamma<-variables [6]*pi/180  # rotation_sam in radians
  
  #Coordinates of the first point of Samarium magnet
  Ax<-variables[4]*constants[4]*cos(beta)   #k_radius_sam*Rin*cos(beta)
  Ay<-variables[4]*constants[4]*sin(beta)   #k_radius_sam*Rin*sin(beta)
  
  #Coordinates of Point C
  Cx<-Ax-variables[7]*cos(beta+gamma)+variables[8]*sin(beta+gamma)
  Cy<-Ay-variables[7]*sin(beta+gamma)-variables[8]*cos(beta+gamma)
  
  #Coordinates of top left point of NdFeB
  Xneo<-constants[4]*cos(variables[2]*constants[7]*pi/180)-variables[3] #Rin.k_radius_neo*cos(angle_neo)-h_neo
  Yneo<-constants[4]*sin(variables[2]*constants[7]*pi/180)
  
  #Coordinates of Point D
  Dx<-Ax+variables[8]*sin(beta+gamma) #Ax+wsin(alfa+gamma)
  Dy<-Ay-variables[8]*cos(beta+gamma) #Ay-wcos(alfa+gamma)

  #Calculate R_air (may be simplified)
  R_air<-(1-variables[9])*sqrt((variables[3]*sin(variables[2]*constants[7]*pi/180))**2+(constants[4]-variables[3]*cos(variables[2]*constants[7]*pi/180))**2)+variables[9]*constants[4]
  
  penalty<-0
  #Calculate penalty values, returns 0 if all constraints are satisfied.
  #C is in radius and doesn't touch NdFeB
  if(Cx>Xneo && Cy<Yneo)
  {
    penalty<-penalty+(Yneo-Cy)^2
  }
  if(Cx<Xneo && Cy<0)
  {
    penalty<-penalty + Cy^2
  }
  #D is in radius
  if(sqrt(Dx^2+Dy^2)>R_air)
  {
    penalty<-penalty + (sqrt(Dx^2+Dy^2) - R_air)^2
  }
  #D is outside NdFeB region
  if(Dx>Xneo && Dy<Yneo)
  {
    penalty<-penalty+(Yneo-Dy)^2
  }
  if(Dx<Xneo && Dy<0)
  {
    penalty<-penalty + Dy^2
  }
  #Top left point of NdFeB is inside the rotor
  if ((atan(Yneo/Xneo)*180/pi)>constants[7])
  {
    penalty<-penalty + ((atan(Yneo/Xneo)*180/pi)-constants[7])^2
  }
  
  return(penalty)
  #Initial true false check
  #return(
    #Condition 1 if true point C is in radius and doesn't touch NdFeB
   # (Cx>Xneo && Cy>Yneo)||(Cx<Xneo && Cy >0) &&
  #Condition 2 if true point D is in radius and doesn't touch NdFeB
#  ((sqrt(Dx^2+Dy^2)<R_air)&&  #inside steel radius including air structure
 #   ((Dx>Xneo && Dy>Yneo)||(Dx<Xneo && Dy >0)))&& #Outside NdFeB region
 	#((atan(Yneo/XNeo)*180/pi)<constants[7]) #Top left point of the NdFeB inside the rotor
  #)
  
  }

# OPTIMIZATION ---------------------------------------------------------
#Require rgenoud package
library("rgenoud")

# Variable names : 1-k_radius_neo, 2- k_angle neo, 3-h_neo, 4-k_radius_sam, 5-k_angle_sam, 6-rotation_sam, 7-L_sam, 8-w_sam, 9-k_extra_air											
limits<-rbind(c(0.9,1),c(0.35,0.75),c(3,20),c(0.4,0.95),c(0.4,0.95),c(0,45),c(5,40),c(5,30),c(0.1,0.8))
#Call optimization function
optimized_results<-genoud(cost,nvars=9, pop.size=50, max.generations=50, wait.generations=5, hard.generation.limit=TRUE,
                          boundary.enforcement=2, BFGS=FALSE, P9=0, project.path="/home/okeysan/Desktop/HTSG/hybrid_pm/genouddene.pro", Domains=limits)

