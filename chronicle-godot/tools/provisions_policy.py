"""A traveller's bounded priorities, using only public choices and inventory."""


class ProvisionsPolicy:
    def __init__(self):
        self.stage = "prepare"
        self.shared = False
        self.visited = False
        self.completed = set()
        self.report_day = None

    def record_success(self, choice):
        action = choice.get("wrapped_action_id", choice["id"])
        self.completed.add(action)
        if action.startswith(("give_food:", "sell_food:")):
            self.shared = True

    def choose(self, response, horizon):
        view = response["observation"]
        player, time = view["player"], view["time"]
        offered = response["choices"]
        enabled = [c for c in offered if c["enabled"] and c.get("hours", 1) <= horizon - time["elapsed_hours"]]

        def action(c):
            return c.get("wrapped_action_id", c["id"])

        def pick(prefix, kind="player_life"):
            return next((c for c in enabled if c["kind"] == kind and action(c).startswith(prefix)), None)

        def travel(fragment):
            return pick(fragment, "travel") or next((c for c in enabled if c["kind"] == "travel" and fragment in c["id"]), None) or next(
                (c for c in enabled if c["kind"] == "travel" and "to_commons" in c["id"]), None)

        def amount(definition):
            return sum(i["quantity"] for i in player.get("inventory", []) if i["definition_id"] == definition)

        smoked = amount("item.smoked_lake_fish")
        roasted = amount("item.roasted_root_portion")
        farm = any(action(c) == "work:recipe.roast_roots" for c in offered)
        fishery = any(action(c) == "work:recipe.smoke_lake_fish" for c in offered)
        if self.stage == "prepare" and smoked > 0:
            self.stage = "visit"
        if self.stage == "visit" and farm:
            self.stage = "local_work"
            self.visited = True
        if self.stage == "local_work" and roasted > 0:
            self.stage = "share"
        if self.stage == "share" and self.shared:
            self.stage = "return"
        if self.stage == "return" and "echo_landing" in view["location"]["id"]:
            self.stage = "home_life"

        if player.get("hunger") in {"high", "extreme"} or (self.stage == "visit" and player.get("hunger") == "medium"):
            meals = [c for c in enabled if action(c).startswith("eat")]
            # The food's public hint states the same benefit the engine applies.
            prepared = next((c for c in meals if "熏湖鱼" in c["label"] or "烤根块" in c["label"]), None)
            if prepared or meals:
                return prepared or meals[0]
        if player.get("fatigue", 0) >= 6 or time["hour"] >= 18 or time["hour"] < 6:
            return pick("rest_block") or pick("rest")
        report = pick("inquire:")
        if report and self.report_day != time["day"]:
            self.report_day = time["day"]
            return report
        if self.stage == "prepare":
            if not fishery:
                return travel("commons_to_fishery")
            return pick("work:recipe.smoke_lake_fish") or pick("gather:")
        if self.stage == "visit":
            return travel("commons_to_terrace_farming") if "echo_terrace" in view["location"]["id"] else travel(".network.")
        if self.stage == "local_work":
            if not farm:
                return travel("commons_to_terrace_farming")
            return pick("work:recipe.roast_roots") or pick("gather:") or pick("ask_local:") or pick("rest")
        if self.stage == "share":
            return pick("give_food:") or pick("sell_food:") or pick("ask_local:") or travel("to_commons")
        if self.stage == "return":
            return travel(".network.")
        if self.stage == "home_life":
            if player["food_count"] < 4:
                return pick("gather:") or travel("commons_to_fishery")
            if fishery and smoked == 0:
                return pick("work:recipe.smoke_lake_fish") or pick("help:")
            return pick("sell_food:") or pick("give_food:") or pick("ask_local:") or pick("rest_block") or pick("rest")
        return None
