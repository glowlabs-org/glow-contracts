import numpy as np
# val = 0,0,0,0,0,0,2000,2000,2000,2000,2000,2000,2000,2000,2000,2500,2500,2500,2500,0,2500,2500,2500,2500,0
# #make a 5x5
# val = np.array(val)
# val = val.reshape(5,5)

#make a 5x5 with 2000  everywher
val = np.full((5,5), 2000)
#transofmt it by multiplying by a 5x5  identity matrix
linear_transofmration = np.identity(5)
print(linear_transofmration)
linear_transofmration[0][0] = 0
val = np.matmul(val, linear_transofmration)
print(val)