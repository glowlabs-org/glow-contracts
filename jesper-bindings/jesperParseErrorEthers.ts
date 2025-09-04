
    import { ethers } from "ethers";
    import { errors } from "./jesper-bindings";
    
    type DebugArg = {
      value: string;
      name: string;
    };
    export const jesperParseError = (errorData: string) => {
      const first4Bytes = errorData.slice(0, 10);
      const error = errors[first4Bytes];
      if (!error) {
        throw new Error(`Unknown error: ${errorData}`);
      }
    
      const abiCoder = new ethers.utils.AbiCoder();
    
      let errorMessage = error.solidityMessageAndArgs.errorMessage;
    
      const _errorData = `0x${errorData.slice(10)}`;
    
      let debugArgs: DebugArg[] = [];
      if (error.solidityMessageAndArgs.args.length > 0) {
        const decoded = abiCoder.decode(
          error.solidityMessageAndArgs.args.map((arg) => arg.type),
          _errorData
        );
        error.solidityMessageAndArgs.args.forEach((arg, i) => {
          const value =
            typeof decoded[i] === "string" ? decoded[i] : decoded[i].toString();
          errorMessage = errorMessage.replace(`{${arg.name}}`, value);
          debugArgs.push({ name: arg.name, value });
        });
      }
      return {
        error,
        errorMessage,
        debugArgs,
      };
    };
    