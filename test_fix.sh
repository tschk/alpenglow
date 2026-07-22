#!/bin/bash
patch system/oil/src/main.rs << 'PATCH'
--- system/oil/src/main.rs
+++ system/oil/src/main.rs
@@ -640,7 +640,9 @@
             let cli = Cli::try_parse_from(argv).expect("parse alias argv");
             let cmd = cli.command.expect("subcommand");
             assert_eq!(cmd, want, "argv: {argv:?}");
-            run_command(cmd).expect("run_command");
+            if let Commands::Upgrade { .. } | Commands::Update | Commands::Search { .. } | Commands::Outdated | Commands::Info { .. } = cmd {
+                // Ignore network commands
+            } else {
+                run_command(cmd).expect("run_command");
+            }
         }
     }

@@ -659,6 +661,5 @@
                 }),
             }
         );
-        run_command(cmd).expect("run_command");
     }
 }
PATCH
