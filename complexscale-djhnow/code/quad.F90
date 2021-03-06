#include "definitions.INC"

MODULE QUAD
USE STRUCTS
IMPLICIT NONE

CONTAINS

!--------------------------------------------------------------------------------------

SUBROUTINE QPOTENTIAL(HAM,PARAMS,MPIDATA,N1,N2,N3,CHARGE)


! POTENTIAL ENERGY MATRIX ELEMENTS APPROXIMATED BY QUADRATURE IN SPHERICAL COORDS
! V IS COMPLETELY DENSE AND SYMMETRIC

! GAUSS-LEGENDRE QUADRATURE USED FOR THETA, PHI AND R

! ONLY SUPPORTED FOR 1 ELECTRON, 1 NUCLEUS AT THE ORIGIN

TYPE(HAMILTONIAN), TARGET, INTENT(INOUT) :: HAM
TYPE(PARAMETERS), INTENT(IN) :: PARAMS
TYPE(MPI_DATA), INTENT(IN) :: MPIDATA
INTEGER, INTENT(IN) :: N1,N2,N3,CHARGE
NUMBER, POINTER :: V(:,:,:,:)
INTEGER :: I,J,K,II,JJ,I1,J1,K1,I2,J2,K2,FIRST,LAST,N,NN,M,ME,NP
REAL *8 :: RAD, DR, PI, DELTA
REAL *8 :: R(1:N1), THETA(1:N2), PHI(1:N3)
REAL *8 :: RW(1:N1), THETAW(1:N2), PHIW(1:N3)
REAL *8 :: A(1:N1,1:N2,1:N3), X(1:N1,1:N2,1:N3)
REAL *8 :: Y(1:N1,1:N2,1:N3), Z(1:N1,1:N2,1:N3)
REAL *8 :: CHI1(1:N1,1:N2,1:N3,1:3), CHI2(1:N1,1:N2,1:N3,1:3)
REAL *8 :: XX(1:N1,1:N2,1:N3), SS(1:N1,1:N2,1:N3,1:3)

IF(MPIDATA % ME == 0) WRITE(*,"(A)") "COMPUTING SPHERICAL POTENTIAL WITH QUADRATURE..."

RAD = 2.0

N = PARAMS % N
M = PARAMS % M
NN = PARAMS % NN
PI = PARAMS % PI
DELTA = PARAMS % DELTA
FIRST = MPIDATA % FIRST
LAST = MPIDATA % LAST
ME = MPIDATA % ME
NP = MPIDATA % NP

V(-N:N,-N:N,-N:N,FIRST:LAST) => HAM % V

! RADIAL NODES AND WEIGHTS
CALL GLNW(R,RW,N1)
R = 0.5*(RAD*R + RAD)
RW = (RAD/2D0)*RW

! THETA NODES AND WEIGHTS
DO I = 1,N2
   THETA(I) = (2D0*PI*(I-1))/N2
   THETAW(I) = (2D0*PI)/N2
END DO

! PHI NODES AND WEIGHTS
CALL GLNW(PHI,PHIW,N3)
PHI = 0.5*(PI*PHI + PI)
PHIW = (PI/2D0)*PHIW

! SAVE X,Y,Z COORDINATES AND OTHER FACTORS

DO K = 1,N3
DO J = 1,N2
DO I = 1,N1

   A(I,J,K) = -CHARGE*RW(I)*THETAW(J)*PHIW(K)*R(I)*SIN(PHI(K))/DELTA**3
   X(I,J,K) = R(I)*COS(THETA(J))*SIN(PHI(K))
   Y(I,J,K) = R(I)*SIN(THETA(J))*SIN(PHI(K))
   Z(I,J,K) = R(I)*COS(PHI(K))

END DO
END DO
END DO

! COMPUTE POTENTIAL ENERGY MATRIX ELEMENTS

X = PI*X/DELTA
Y = PI*Y/DELTA
Z = PI*Z/DELTA

SS(:,:,:,1) = SIN(X)
SS(:,:,:,2) = SIN(Y)
SS(:,:,:,3) = SIN(Z)

!OMP PARALLEL DO PRIVATE(I1,J1,K1,I2,J2,K2,JJ,CHI1,CHI2) SHARED(A,X,Y,Z,SS)

DO JJ = FIRST,LAST

   K2 = (JJ-1)/NN**2 - N
   J2 = (JJ-(K2+N)*NN**2-1)/NN - N
   I2 = JJ-(K2+N)*NN**2-(J2+N)*NN-N-1

   CALL EVALBASIS(X,Y,Z,XX,SS,CHI2,I2,J2,K2)

   DO K1 = -N,N
   DO J1 = -N,N
   DO I1 = -N,N

      CALL EVALBASIS(X,Y,Z,XX,SS,CHI1,I1,J1,K1)
      V(I1,J1,K1,JJ) = SUM(A*CHI1(:,:,:,1)*CHI1(:,:,:,2)*CHI1(:,:,:,3) &
                            *CHI2(:,:,:,1)*CHI2(:,:,:,2)*CHI2(:,:,:,3))

   END DO
   END DO
   END DO

   IF(ME == NP-1) WRITE(*,"(A,I6,A,I6)") "CURRENTLY AT COLUMN ",JJ," OUT OF ",M

END DO

!OMP END PARALLEL DO

END SUBROUTINE QPOTENTIAL

!--------------------------------------------------------------------------------------

SUBROUTINE EVALBASIS(X,Y,Z,XX,SS,CHI,I,J,K)

INTEGER, INTENT(IN) :: I,J,K
REAL *8, INTENT(IN) :: X(:,:,:), Y(:,:,:), Z(:,:,:), SS(:,:,:,:)
REAL *8, INTENT(OUT) :: CHI(:,:,:,:), XX(:,:,:)
REAL *8 :: PI

PI = 4D0*ATAN(1D0)

XX = X - I*PI
CHI(:,:,:,1) = SS(:,:,:,1)/XX
WHERE(XX == 0)
   CHI(:,:,:,1) = 1D0
END WHERE
   
XX = Y - J*PI
CHI(:,:,:,2) = SS(:,:,:,2)/XX
WHERE(XX == 0)
   CHI(:,:,:,2) = 1D0
END WHERE

XX = Z - K*PI
CHI(:,:,:,3) = SS(:,:,:,3)/XX
WHERE(XX == 0)
   CHI(:,:,:,3) = 1D0
END WHERE

CHI = CHI*((-1)**(I+J+K))


END SUBROUTINE EVALBASIS

!--------------------------------------------------------------------------------------

SUBROUTINE GLNW(X,W,N)

INTEGER :: I,J,N,M,N1,N2,K
REAL *8 :: X(1:N), W(1:N), EPS, XX, DX, PI
REAL *8, ALLOCATABLE :: X0(:), L(:,:), LP(:)

PI = 4D0*ATAN(1D0)

M = N-1
N1 = M+1 
N2 = M+2

DX = 2D0/(N1-1)
EPS = 1D-15

ALLOCATE(X0(M+1),L(N1,N2),LP(N1))

DO I = 0,M
   XX = -1D0 + I*DX
   X(I+1) = COS((2*I+1)*PI/(2D0*M+2D0)) + (0.27/N1)*SIN(PI*XX*M/N2);
END DO

L = 0
LP = 0
X0 = 2
K = 0

DO WHILE(MAXVAL(ABS(X-X0)) > EPS)

    L(:,1) = 1D0
    L(:,2) = X
    
    DO I = 2,N1
       L(:,I+1) = (1D0/I)*((2*I-1)*X*L(:,I)-(I-1)*L(:,I-1))
    END DO
    
    LP = N2*(L(:,N1)-X*L(:,N2))/(1D0 - X**2)
    X0 = X
    X = X0 - L(:,N2)/LP
    K = K + 1
     
END DO

W = (REAL(N2,8)/REAL(N1,8))**2*2D0/((1D0-X**2)*LP**2)

END SUBROUTINE GLNW

!--------------------------------------------------------------------------------------

SUBROUTINE MPIDENSEMULT(V,X,Y,M,MB,MPIDATA)

INTEGER, INTENT(IN) :: M,MB
TYPE(MPI_DATA), INTENT(IN) :: MPIDATA
NUMBER, INTENT(IN) :: V(1:M,1:MB), X(1:MB)
NUMBER, INTENT(OUT) :: Y(1:MB)
NUMBER, ALLOCATABLE, SAVE :: Z(:)
LOGICAL, SAVE :: FIRSTTIME = .TRUE.
INTEGER :: MPIERR

IF(FIRSTTIME) THEN
   FIRSTTIME = .FALSE.
   ALLOCATE(Z(M))
END IF

CALL DGEMV('N',M,MB,1D0,V,M,X,1,0D0,Z,1)
CALL MPI_REDUCE_SCATTER(Z,Y,MPIDATA%BLOCKS,MPIDATA%MPISIZE,MPI_SUM,MPIDATA%COMM,MPIERR)

END SUBROUTINE MPIDENSEMULT

!--------------------------------------------------------------------------------------

END MODULE QUAD