use std::thread;

fn main() {
    let _ = thread::spawn(|| {
        println!("Background thread");
    }).join();
}
