"""Legal adventure policies, native continuity and source/package parity.

This is code-agent play, not a claim of human enjoyment or measured playtime.
No state injection, forced dice, remote inventory inspection or free rewards.
"""
import argparse
import json
from pathlib import Path
import time

from agent_play import ChronicleClient
from verify_journey_package import SAVES, TRUTH


def play(output, packaged, seed, policy):
    name = f"roaming_{seed}_{policy}_{'package' if packaged else 'source'}"
    trace_path = output / (name + '.jsonl')
    metrics = {'seed': seed, 'policy': policy, 'actions': 0, 'sales': 0, 'buys': 0,
               'combat_rounds': 0, 'resolved_events': [], 'max_action_seconds': 0.0}
    with ChronicleClient(packaged=packaged, timeout=90) as game, trace_path.open('w', encoding='utf-8') as log:
        def request(command, **arguments):
            began = time.monotonic()
            result = game.request(command, **arguments)
            seconds = time.monotonic() - began
            log.write(json.dumps({'command': command, 'arguments': arguments, 'seconds': seconds,
                                  'response': result}, ensure_ascii=False) + '\n')
            log.flush()
            assert result.get('ok'), result
            if command == 'act':
                metrics['actions'] += 1
                metrics['max_action_seconds'] = max(seconds, metrics['max_action_seconds'])
            return result

        state = request('start', mode='play', scenario='echo_realm', seed=seed, economy_variant='world_roaming_v1')
        assert state['observation']['player']['coins'] == 12

        def rows(prefix='', kind=None):
            return [c for c in state['choices'] if c['enabled'] and c['id'].startswith(prefix)
                    and (kind is None or c['kind'] == kind)]

        def take(identifier):
            nonlocal state
            option = next((c for c in rows() if c['id'] == identifier), None)
            assert option is not None, (identifier, state['observation'].get('journey_event'),
                                        [(c['id'], c.get('blocked_reason')) for c in state['choices']])
            state = request('act', choice_id=option['choice_id'])
            if identifier.startswith('adventure:'):
                event = identifier.split(':')[1]
                if not any(c['id'].startswith('adventure:' + event + ':') for c in state['choices']):
                    metrics['resolved_events'].append(event)
            if option['kind'] == 'combat_encounter':
                metrics['combat_rounds'] += 1
            assert not identifier.startswith(('work:', 'gather:', 'help:')), 'Adventure requires no compulsory labor'

        def route(identifier):
            take(identifier)
            for _ in range(6):
                if not state['observation']['player']['travel_remaining']:
                    return
                take('continue')
            raise AssertionError('Travel did not finish')

        def equip(fragment):
            options = [c for c in rows('equip:') if fragment in c['label']]
            assert options, fragment
            take(options[0]['id'])

        def meal():
            if state['observation']['player']['hunger'] in ('medium', 'high', 'extreme') and rows('eat'):
                take(rows('eat')[0]['id'])

        take('adventure:arrival_signs:forest')
        route('journey_route.generated_location.echo_landing.commons.journey_location.forest_edge')
        take('adventure:forest_sound:' + ('listen' if policy == 'explorer' else 'tracks'))
        take('adventure:forest_satchel:take')
        equip('短鞭')
        route('journey_route.journey_location.forest_edge.journey_location.broken_bridge')
        take('adventure:bridge_crossing:ford' if rows('adventure:bridge_crossing:ford') else 'adventure:bridge_crossing:round')
        take('adventure:bridge_equipment:' + ('vest' if policy == 'explorer' else 'shoes'))
        equip('护衣' if policy == 'explorer' else '路鞋')
        route('journey_route.journey_location.broken_bridge.journey_location.forest_edge')
        take('adventure:forest_return:mark')
        route('journey_route.journey_location.forest_edge.generated_location.echo_landing.commons')
        route('generated_route.echo_landing.commons_to_fishery')
        take('adventure:shore_box:hook')
        for _ in range(2):
            sales = rows('sell_food:')
            if not sales:
                break
            before = state['observation']['player']['coins']
            take(sales[0]['id'])
            assert state['observation']['player']['coins'] > before
            metrics['sales'] += 1
        for option in rows('ask_local:')[:1]:
            take(option['id'])
            assert not rows('ask_local:')
            assert '答复' in state['observation']['feedback']['title']
        if rows('buy:'):
            take(rows('buy:')[0]['id'])
            metrics['buys'] += 1
        meal()
        route('generated_route.echo_landing.fishery_to_commons')
        if policy == 'explorer':
            route('generated_route.echo_landing.commons_to_watch_service')
            take('adventure:beacon_marks:study')
            route('journey_route.generated_location.echo_landing.watch_post.journey_location.old_beacon')
            take('adventure:beacon_climb:known')
            take('adventure:beacon_view:remember')
            route('journey_route.journey_location.old_beacon.generated_location.echo_landing.watch_post')
            route('generated_route.echo_landing.watch_service_to_commons')
        else:
            # Follow the offered public road to the other settlement, not a teleport.
            cross = next(c for c in rows(kind='travel') if '.network.' in c['id'])
            route(cross['id'])
            take('adventure:notice_at_commons:read')
            route('journey_route.generated_location.echo_terrace.commons.journey_location.waystone')
            take('adventure:waystone_marks:remember')
            for _ in range(6):
                if rows('adventure:waystone_night:known'):
                    break
                meal()
                take('rest')
            take('adventure:waystone_night:known')
            take('adventure:waystone_cache:take')
            route('journey_route.journey_location.waystone.generated_location.echo_terrace.commons')
            cross = next(c for c in rows(kind='travel') if '.network.' in c['id'])
            route(cross['id'])
        meal()
        inn = next(c for c in rows(kind='travel') if '客舍' in c['label'])
        route(inn['id'])
        for _ in range(8):
            available = rows('adventure:night_talk:listen') or rows('adventure:tell_bridge:share') or rows('adventure:host_remembers_bridge:ask')
            if available:
                take(available[0]['id'])
                if 'host_remembers_bridge' in metrics['resolved_events']:
                    break
            else:
                meal()
                take('rest')
        assert 'tell_bridge' in metrics['resolved_events'], 'No physical host conversation'
        assert 'host_remembers_bridge' in metrics['resolved_events'], 'Previous encounter did not open a new topic'
        if rows('service:drink'):
            take('service:drink')
        assert metrics['sales'] > 0, 'Actual food sale missing'
        assert metrics['buys'] > 0, 'Actual purchase missing'
        assert state['observation']['player']['health'] > 40
        slot = f"roam_{seed}_{policy}_{int(packaged)}_{time.time_ns()}"
        request('save', slot=slot)
        assert request('load', slot=slot)['observation'] == state['observation']
        take('rest')
        request('save', slot=slot, overwrite=True)
        native = json.loads((SAVES / (slot + '.json')).read_text(encoding='utf-8'))
        metrics.update({'hours': state['observation']['time']['elapsed_hours'],
                        'health': state['observation']['player']['health'],
                        'food': state['observation']['player']['food_count'],
                        'coins': state['observation']['player']['coins']})
        (output / (name + '.native.json')).write_text(json.dumps(native, ensure_ascii=False), encoding='utf-8')
        return native, metrics


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--source-only', action='store_true')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    cases = []
    for seed, policy in ((81001, 'explorer'), (89037, 'night')):
        source, metrics = play(args.output, False, seed, policy)
        if not args.source_only:
            package, _ = play(args.output, True, seed, policy)
            for key in TRUTH:
                assert source[key] == package[key], (seed, policy, key)
        cases.append(metrics)
        print(json.dumps(metrics, ensure_ascii=False), flush=True)
    (args.output / 'result.json').write_text(json.dumps({'cases': cases, 'passed': True,
        'source_only': args.source_only, 'kind': 'legal_code_agent_play_not_human',
        'truth_keys': [] if args.source_only else list(TRUTH)}, ensure_ascii=False, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
