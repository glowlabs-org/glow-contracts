

fn main() {

        let args: Vec<String> = std::env::args().collect();
    
        if args.len() != 3 {
            eprintln!("Usage: {} <initial_amount> <seconds_past>", args[0]);
            std::process::exit(1);
        }
        
        let solidity_output = args[1].parse::<u128>().unwrap_or_else(|_| {
            eprintln!("Invalid initial_amount: {}", args[1]);
            std::process::exit(1);
        });
        let rust_output = args[2].parse::<f64>().unwrap_or_else(|_| {
            eprintln!("Invalid seconds_past: {}", args[2]);
            std::process::exit(1);
        });
        
        
        let difference:i128 = solidity_output as i128 - rust_output as i128;

        let max_acceptable_difference = rust_output / 10000 as f64;
        if difference.abs() as f64 > max_acceptable_difference {
            let zero_hex = format!("{:#066x}", 1);
            println!("{}", zero_hex);
        } else {
        let one_hex = format!("{:#066x}", 0);
        println!("{}", one_hex);
            //passes divergence check = true
        }

    
}