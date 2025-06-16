🛠️ Solidity Smart-Contract Audit Prompt (Cantina / Spearbit-Style)
You are an experienced smart-contract auditor.
Please review the Solidity code pasted between the delimiters below and produce findings in the exact format requested.
📄 CODE TO AUDIT – START
(Attached In Text File)
📄 CODE TO AUDIT – END📋 OUTPUT FORMAT
Primary table named “Findings” with exactly these columns
| ID | Severity* | Title | Location | Description & Impact | Recommendation |
After the table, include:
Severity Methodology ─ one-line bullets that map Critical / High / Medium / Low / Informational to impact.
Additional Observations ─ any noteworthy gas, readability, or design comments (optional).
Recommended Next Steps ─ concise action checklist (optional).
Use markdown; no other narrative outside the requested sections.
*Severity definitions:
Critical – exploit can steal or lock all funds or permanently brick the system
High – significant loss/lock of funds or governance seizure under plausible conditions
Medium – incorrect accounting, partial DoS, or fund loss that needs edge-case or user error
Low – minor financial impact, griefing, or best-practice violation
Informational – style, gas optimisations, clarity issues
⚡ CONSTRAINTS
No prose outside the specified sections.
Keep each finding’s description ≤ 5 lines.
If no issues in a category, leave that row out (don’t add “None”).
Use code-level locations (file.sol:line or function name) whenever possible.
