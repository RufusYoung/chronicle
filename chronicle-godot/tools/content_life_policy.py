"""Bounded artisan/explorer policy; consumes only the formal public observation."""


class ContentLifePolicy:
    def __init__(self):
        self.completed = set()
        self.shop_waits = 0

    def choose(self, response, horizon):
        view = response["observation"]
        player, time = view["player"], view["time"]
        remaining = horizon - time["elapsed_hours"]
        offered = response["choices"]
        enabled = [c for c in offered if c["enabled"] and c.get("hours", 1) <= remaining]

        def action(c):
            return c.get("wrapped_action_id", c["id"])

        def pick(prefix, kind="player_life"):
            return next((c for c in enabled if c["kind"] == kind and action(c).startswith(prefix)), None)

        def travel(fragment):
            return next((c for c in enabled if c["kind"] == "travel" and fragment in c["id"]), None) or next(
                (c for c in enabled if c["kind"] == "travel" and "to_commons" in c["id"]), None)

        def at(recipe):
            return any(action(c) == "work:recipe." + recipe for c in offered)

        choice = None
        if player.get("hunger") in {"high", "extreme"}:
            choice = pick("eat")
        if choice is None and (player.get("fatigue", 0) >= 6 or time["hour"] >= 18 or time["hour"] < 6):
            choice = pick("rest_block") or pick("rest")
        if choice is None:
            choice = pick("inquire:")
        inventory = player.get("inventory", [])
        ropes = [i for i in inventory if i["definition_id"] in
                 {"item.light_reed_cord", "item.doubled_reed_cord", "item.fiber_rope"}]
        light_count = sum(i["quantity"] for i in ropes if i["definition_id"] == "item.light_reed_cord")
        strong = any(i["definition_id"] == "item.doubled_reed_cord" for i in ropes)
        if choice is None and player["food_count"] < 4:
            choice = (pick("work:recipe.net_fishing") if strong else None) or pick("gather:") or travel("commons_to_fishery")
        if strong:
            self.completed.add("strong_tool_owned")
        if choice is None and "strong_tool_owned" not in self.completed:
            if player["coins"] < 3 and not ropes:
                choice = pick("help:") if at("net_fishing") else travel("commons_to_fishery")
                choice = choice or pick("sell_food:")
            elif not at("reed_cordage"):
                choice = travel("commons_to_reed_craft")
            elif light_count >= 2:
                choice = pick("work:recipe.double_light_cords")
            elif ropes:
                choice = pick("work:recipe.reed_cordage") or pick("repair:")
            else:
                choice = next((c for c in enabled if action(c).startswith("buy:") and "细苇绳" in c["label"]), None)
                if choice is None:
                    self.shop_waits += 1
                    if self.shop_waits % 5 == 0:
                        choice = travel("to_commons")
        if choice is None and "strong_tool_owned" in self.completed:
            if "work:recipe.smoke_lake_fish" not in self.completed:
                choice = (pick("work:recipe.smoke_lake_fish") or pick("work:recipe.net_fishing") or pick("repair:")) if at("net_fishing") else travel("commons_to_fishery")
            elif not any(a.startswith("give_food:") for a in self.completed):
                choice = pick("give_food:") or pick("ask_local:") or travel("to_commons")
            else:
                choice = travel("commons_to_terrace_farming")
                if not any("commons_to_terrace_farming" in c["id"] for c in offered) and "terrace" not in view["location"]["id"]:
                    choice = travel(".network.")
        if choice is None:
            choice = pick("ask_local:") or pick("", "wait")
        return choice

    def record_success(self, choice):
        self.completed.add(choice.get("wrapped_action_id", choice["id"]))
