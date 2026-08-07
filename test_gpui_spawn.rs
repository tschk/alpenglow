use gpui::*;

struct TestView {
    val: i32,
}

impl TestView {
    fn new(cx: &mut Context<Self>) -> Self {
        // use spawn to do background work
        cx.spawn(|this, mut cx| async move {
            let val = cx.background_executor().spawn(async {
                42
            }).await;

            this.update(&mut cx, |this, cx| {
                this.val = val;
                cx.notify();
            }).ok();
        }).detach();

        Self { val: 0 }
    }
}

fn main() {}
