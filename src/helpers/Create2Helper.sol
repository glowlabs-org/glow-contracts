import  {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

contract Create2Helper {
    function deploy(bytes32 salt, bytes memory bytecode) public returns (address) {
        return Create2.deploy(0, salt, bytecode);
    }

    function computeAddress(bytes32 salt, bytes memory bytecode) public view returns (address) {
        return computeAddress(salt, bytecode,address(this));
    }

    function computeAddress(bytes32 salt, bytes memory bytecode, address deployer) public pure returns (address) {
        bytes32 bytecodeHash = keccak256(bytecode);
        return Create2.computeAddress(salt,bytecodeHash,deployer );
    }
}