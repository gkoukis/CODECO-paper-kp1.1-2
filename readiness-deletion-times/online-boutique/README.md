This script automates repeated deploy/delete cycles of the Online Boutique app in a given namespace, waiting until the frontend is 
truly reachable via HTTP 200, measures deployment and deletion times per iteration, logs them to CSV and TXT files 
in an append-only fashion, and prints overall min/max/avg statistics for that run.
