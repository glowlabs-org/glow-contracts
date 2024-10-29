import os 

#
import json


inde_file_texts = []
contracts = [
    "CarbonCreditDescendingPriceAuction.sol",
    "GrantsTreasury.sol",
     "USDG.sol",
    "SafetyDelay.sol",
    "MinerPoolAndGCA.sol",
    "EarlyLiquidity.sol",
    "GCC.GuardedLaunch.sol",
    "Governance.sol",
    "Glow.GuardedLaunch.sol",
    "GrantsTreasury.sol",
    "ImpactCatalyst.sol",
    "VetoCouncil.sol",
    "Glow.GuardedLaunch.sol",

]

for contract in contracts:
    file_in_dir = os.listdir("out/"+ contract + "/")
    print(file_in_dir)
    
    contract_name = file_in_dir[0]
    
    print(contract_name)
    if("IDecimals" in contract_name):
        contract_name = "EarlyLiquidity.json"

    file = open("out/"+contract+ "/"+ contract_name ,"r")
    data = json.load(file)
    #save the abi in a variable
    abi  = data["abi"]

    contract_name_without_json = contract_name.split(".")[0]
    text_to_write =  f"export const {contract_name_without_json}{'ABI'} = {json.dumps(abi,indent=4)}"

    index_file_text = f"export * from './{contract_name_without_json}.abi';\n"
    inde_file_texts.append(index_file_text)

    with open("abis/" + contract_name_without_json +'.abi' +".ts", "w") as f:
        f.write(text_to_write)

with open("abis/index.ts", "w") as f:
    f.writelines(inde_file_texts)