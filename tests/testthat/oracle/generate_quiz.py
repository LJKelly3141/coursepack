# tests/testthat/oracle/generate_quiz.py
# Test oracle only. Runs the snapshot Python generator on a bank so the R port
# can be compared against it. Never shipped as behaviour.
import json, sys, importlib.util, pathlib, types
snap, bank_dir, spec_json, stage = sys.argv[1:5]
spec = importlib.util.spec_from_file_location("generate_resources", pathlib.Path(snap) / "generate_resources.py")
gr = importlib.util.module_from_spec(spec); spec.loader.exec_module(gr)
s = json.loads(pathlib.Path(spec_json).read_text())
item = {"title": s["title"], "type": "Quizzes::Quiz", "published": s.get("published", True), "generate": dict(s["bank"], kind="quiz", bank=".")}
module = {"title": s["module_title"]}
course = {"assignment_groups": [{"name": s["group"], "id": s["group_id"]}], "term": {"timezone": s["tz"]}}
res = gr.generate_item(item, module, course, bank_dir, stage, rid=s["quiz_id"], warnings=[])
print(json.dumps([r[0] for r in res]))
