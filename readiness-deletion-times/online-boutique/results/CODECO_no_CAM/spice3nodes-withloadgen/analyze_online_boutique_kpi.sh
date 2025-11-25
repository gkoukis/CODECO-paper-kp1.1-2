#!/usr/bin/env bash

# Copyright (c) 2025 Athena RC.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0
#
# Contributors:
#      George Koukis - author

set -euo pipefail

CSV_FILE_DEFAULT="online-boutique_kpi_results.csv"

CSV="${1:-$CSV_FILE_DEFAULT}"

if [[ ! -f "$CSV" ]]; then
  echo "ERROR: CSV file not found: $CSV"
  echo "Usage: $0 [csv_file]"
  exit 1
fi

echo "Analyzing KPI data from: $CSV"
echo "======================================================="

awk -F',' '
NR==1 { next }  # skip header
{
  dep = $4 + 0.0
  del = $5 + 0.0

  # Deployment stats
  nD++
  sumD  += dep
  sumSqD += dep * dep
  if (nD == 1 || dep < minD) minD = dep
  if (nD == 1 || dep > maxD) maxD = dep

  # Deletion stats
  nE++
  sumE  += del
  sumSqE += del * del
  if (nE == 1 || del < minE) minE = del
  if (nE == 1 || del > maxE) maxE = del
}
END {
  if (nD > 0) {
    meanD = sumD / nD
    varD  = sumSqD / nD - (meanD * meanD)
    if (varD < 0) varD = 0
    sdD   = sqrt(varD)

    printf("Deployment time stats (seconds) over %d runs:\n", nD)
    printf("  min   = %.3f\n", minD)
    printf("  max   = %.3f\n", maxD)
    printf("  mean  = %.3f\n", meanD)
    printf("  stdev = %.3f\n\n", sdD)
  } else {
    print "No deployment data found.\n"
  }

  if (nE > 0) {
    meanE = sumE / nE
    varE  = sumSqE / nE - (meanE * meanE)
    if (varE < 0) varE = 0
    sdE   = sqrt(varE)

    printf("Deletion time stats (seconds) over %d runs:\n", nE)
    printf("  min   = %.3f\n", minE)
    printf("  max   = %.3f\n", maxE)
    printf("  mean  = %.3f\n", meanE)
    printf("  stdev = %.3f\n", sdE)
  } else {
    print "No deletion data found."
  }
}
' "$CSV"
