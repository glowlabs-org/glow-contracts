fn remaining_amount(initial_amount: f64, seconds_past: u128) -> f64 {
    const SECONDS_IN_A_DAY: u128 = 86400; // 24 * 60 * 60
    const HALF_LIFE_IN_DAYS: f64 = 365.0;
    
    let days_past = seconds_past as f64 / SECONDS_IN_A_DAY as f64;
    initial_amount * (0.5f64).powf(days_past / HALF_LIFE_IN_DAYS)
}


fn main() {
    let args: Vec<String> = std::env::args().collect();

    if args.len() != 3 {
        eprintln!("Usage: {} <initial_amount> <seconds_past>", args[0]);
        std::process::exit(1);
    }
    
    let initial_amount = args[1].parse::<f64>().unwrap_or_else(|_| {
        eprintln!("Invalid initial_amount: {}", args[1]);
        std::process::exit(1);
    });
    let seconds_past = args[2].parse::<u128>().unwrap_or_else(|_| {
        eprintln!("Invalid seconds_past: {}", args[2]);
        std::process::exit(1);
    });
    
    let remaining:f64 = remaining_amount(initial_amount, seconds_past);
    //Conv
    let remaining_as_uint: u128 = remaining as u128;
    //print as hex
    let str_remaining = format!("{:#066x}", remaining_as_uint);
    println!("{}", str_remaining);

    return;
}