"""Read-only audit of physical contacts, transmitted information and later choices."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path

from audit_resident_life import audit as audit_life


def audit(path: Path) -> dict:
    raw = path.read_bytes()
    envelope = json.loads(raw)
    fixture = envelope["bootstrap"]["fixture_data"]
    facts = envelope["stores"]["facts"]
    index = {f["fact_id"]: f for f in facts}
    people = {e["id"]: e for e in fixture["entities"] if "generated_resident" in e.get("tags", [])}

    def settlement(person):
        return people.get(person, {}).get("states", {}).get("settlement_id", "")

    def ancestry(fact):
        pending, seen = list(fact.get("source_fact_ids", [])), set()
        while pending:
            key = pending.pop()
            if key in seen or key not in index:
                continue
            seen.add(key)
            pending.extend(index[key].get("source_fact_ids", []))
        return seen

    conversations = [f for f in facts if f["fact_type"] == "community_conversation"]
    cross_contacts = [f for f in conversations if settlement(f["actor_id"]) != settlement(f["target_id"])]
    messages = [f for f in facts if f["fact_type"] == "community_message_heard"]
    policies = [f for f in facts if f["fact_type"] == "community_policy_changed"]
    trades = [f for f in facts if f["fact_type"] == "resident_food_purchased"]
    cross_trades = [f for f in trades if settlement(f["actor_id"]) != settlement(f["target_id"])]
    refusals = [f for f in facts if f["fact_type"] == "resident_food_purchase_unmet" and f.get("reason") == "community_reserve"]
    message_ids = {f["fact_id"] for f in messages}
    policy_ids = {f["fact_id"] for f in policies}
    meals = [f for f in facts if f["fact_type"] in {"npc_self_meal", "npc_household_shared_food", "npc_cross_household_shared_food"}]
    chains = []
    for event in cross_trades + refusals:
        prior = ancestry(event)
        if not prior.intersection(message_ids):
            continue
        followups = [f for f in facts if f.get("actor_id") == event["actor_id"]
                     and f.get("fact_type") in {"resident_activity_changed", "npc_livelihood_produced"}
                     and event["fact_id"] in ancestry(f)]
        descendants = [f["fact_id"] for f in meals if event["fact_id"] in ancestry(f)]
        chains.append({"structure": "report>cross_trade>meal" if event in cross_trades else "reported_policy>refusal>alternative",
                       "event": event["fact_id"], "actor_id": event["actor_id"], "target_id": event.get("target_id"),
                       "messages": sorted(prior & message_ids), "policies": sorted(prior & policy_ids),
                       "followup_choices_or_work": [f["fact_id"] for f in followups], "meals": descendants})
    policy_feedback = []
    for policy in policies:
        prior = ancestry(policy)
        foreign_needs = [index[k] for k in prior if index[k].get("fact_type") == "community_observation"
                         and index[k].get("topic") == "need" and index[k].get("payload", {}).get("needs_food")
                         and settlement(index[k]["actor_id"]) != settlement(policy["actor_id"])]
        if foreign_needs:
            policy_feedback.append({"policy": policy["fact_id"], "needs": [f["fact_id"] for f in foreign_needs],
                                    "mode": policy["payload"]["policy"]})
    assistance = []
    withheld = [f for f in facts if f["fact_type"] == "community_aid_withheld"]
    for order in envelope["stores"]["exchanges"]:
        if not order.get("community_request_id"):
            continue
        receipts = [f for f in facts if f.get("exchange_id") == order["exchange_id"]
                    and f["fact_type"] == "food_hauling_stocked"]
        receipt_ids = {f["fact_id"] for f in receipts}
        recipient_meals = [f for f in meals if f.get("target_id") in order["recipient_ids"]
                           and receipt_ids.intersection(ancestry(f))]
        responses = [f for f in facts if f["fact_type"] == "community_observation"
                     and f.get("topic") == "need" and not f["payload"].get("needs_food")
                     and f["actor_id"] in order["recipient_ids"] and receipt_ids.intersection(ancestry(f))]
        response_ids = {f["fact_id"] for f in responses}
        returned_messages = [f for f in messages if f["actor_id"] == order["party_a"]
                             and f.get("root_fact_id") in response_ids]
        return_ids = {f["fact_id"] for f in returned_messages}
        later_rules = [f["fact_id"] for f in policies if f["actor_id"] == order["party_a"]
                       and return_ids.intersection(ancestry(f))]
        prior_refusals = [f["fact_id"] for f in withheld if f["actor_id"] == order["party_a"]
                         and f.get("requester_id") == order["requester_id"]
                         and f["day"] * 24 + f["hour"] < order["created_tick"]]
        assistance.append({"exchange_id": order["exchange_id"], "donor": order["party_a"],
                           "carrier": order["party_b"], "requester": order["requester_id"],
                           "self_delivery": order.get("self_delivery", False),
                           "status": order["status"], "quantity": order["quantity"],
                           "cross_settlement": settlement(order["party_a"]) != settlement(order["requester_id"]),
                           "request": order["community_request_id"], "root_request": order["request_root_fact_id"],
                           "receipts": sorted(receipt_ids), "paid_fees": sum(f.get("fee_paid", 0) for f in receipts),
                           "recipient_meal_ancestry": [f["fact_id"] for f in recipient_meals],
                           "satisfied_reports": sorted(response_ids), "returned_messages": sorted(return_ids),
                           "later_rules": later_rules, "earlier_withholding": prior_refusals})
    life = audit_life(path)
    return {
        "checkpoint": str(path), "sha256": hashlib.sha256(raw).hexdigest(),
        "elapsed_hours": envelope["world_time"]["elapsed_hours"], "seed": fixture.get("challenge_seed"),
        "test_injections": [f["fact_id"] for f in facts if f["fact_type"] == "test_injection"],
        "community_counts": dict(Counter(f["fact_type"] for f in facts if f["fact_type"].startswith("community_"))),
        "cross_contacts": len(cross_contacts), "cross_trade_count": len(cross_trades),
        "cross_trade_spend": sum(f["fields"]["total_price"] for f in cross_trades),
        "policies": dict(Counter(f["payload"]["policy"] for f in policies)),
        "actual_policy_transitions": sum(f.get("previous_policy") != f["payload"]["policy"] for f in policies),
        "cross_need_policy_feedback": policy_feedback, "chains": chains,
        "refusals": len(refusals), "food_balance_remainder": life["food_balance_remainder"],
        "currency_balance_remainder": life["initial_currency"] - life["remaining_currency"],
        "meals": life["consumed_meals"], "longest_meal_gap_hours": max(p["longest_meal_gap_hours"] for p in life["residents"]),
        "minimum_resident_meals": min(p["meals"] for p in life["residents"]),
        "hauling_orders": life["hauling_orders"], "hauling_paid_fees": life["hauling_paid_fees"],
        "community_assistance": assistance, "assistance_orders": len(assistance),
        "assistance_settled": sum(r["status"] == "settled" for r in assistance),
        "assistance_withheld": len(withheld),
        "assistance_returned_information": sum(bool(r["returned_messages"]) for r in assistance),
        "assistance_policy_feedback": sum(bool(r["later_rules"]) for r in assistance),
        "assistance_recovery": sum(bool(r["earlier_withholding"] and r["receipts"]) for r in assistance),
        "ancestry_scope": "Mixed stacks retain contributing-batch ancestry, not exclusive ownership of each eaten unit. Message ancestry alone does not prove a changed choice; compare aligned mechanism ablations.",
        "residents": life["residents"],
        "scope": "Read-only passive-world causal citations. Contacts, announcements and counts are not economic or E2 acceptance; inspect physical custody and aligned ablations. Not human play.",
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checkpoint", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = audit(args.checkpoint)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k not in {"residents", "chains", "cross_need_policy_feedback", "community_assistance"}}, ensure_ascii=True, indent=2))
