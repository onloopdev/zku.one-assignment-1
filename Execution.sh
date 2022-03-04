## install circom
## --------------
#https://docs.circom.io/getting-started/installation/#installing-dependencies

## compile circuit
## ---------------
##  - generates R1CS constraint system, wasm code, 
##      debugging labels, and C/C++ code needed 
##      for witness gen
circom merkle_root.circom --r1cs --wasm --sym --c

## install dependencies
## --------------------
#sudo apt install -y nlohmann-json3-dev
#sudo apt install -y libgmp-dev
#sudo apt install -y nasm

## copy the input files into the witness generator system
## ------------------------------------------------------
cp input.json merkle_root_cpp/
cp input.json merkle_root_js/

## generate the witness
## --------------------
##  - witness: this is the statement we wish to prove but do not want to reveal
cd merkle_root_cpp
# execute c++ code to generate executionable
make
# execute generated file to output witness, extract withness 
./merkle_root input.json witness.wtns
mv witness.wtns ..

## return to root
## --------------
cd ..

## initiate powers of tau ceremony
## -------------------------------
##  - here we produce partial public parameters that can be used by all participants that wish to use zk-SNARKs.
##    in order to protect the parameters from compromise, the ceremony leverages a multi-party computation protocol
##    the so called powers of tau : https://www.zfnd.org/blog/conclusion-of-powers-of-tau/
snarkjs powersoftau new bn128 12 pot12_0000.ptau -v
snarkjs powersoftau contribute pot12_0000.ptau pot12_0001.ptau --name="First contribution" -v
snarkjs powersoftau prepare phase2 pot12_0001.ptau pot12_final.ptau -v
snarkjs groth16 setup merkle_root.r1cs pot12_final.ptau merkle_root_0000.zkey

## generate proof
## --------------
##  - encodes proof with (semi) homomorhpic function
snarkjs zkey contribute merkle_root_0000.zkey merkle_root_0001.zkey --name="1st Contributor Name" -v
snarkjs zkey export verificationkey merkle_root_0001.zkey verification_key.json
snarkjs groth16 prove merkle_root_0001.zkey witness.wtns proof.json public.json

## verify proof
## ------------
##  - this is a similator which can interact with the proof, and "permute it" until a true bool is recieved

## through circuit
snarkjs groth16 verify verification_key.json public.json proof.json

## through contract
snarkjs zkey export solidityverifier merkle_root_0001.zkey verifier.sol

## console call for verification check-by-eye
snarkjs generatecall
