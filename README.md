### Warcraft 3 Replay Parser for Perl

This module attempts to parse the replay files of the game Warcraft III [The Frozen Throne] from Blizzard.

It tries to follow as close as possible the format described by 'blue' and 'nagger' from [w3g.deepnode.de](http://w3g.deepnode.de).
This module is only possible because of their awesome work. The PHP [replay parser](http://w3rep.sourceforge.net/) by Julas was very helpfull as well.


#### SYNOPSIS
```perl
use WC3ReplayParser;
my $replay = WC3ReplayParser::parse('replay-filename.w3g');
# or
my $replay = WC3ReplayParser::parse(\$replay_bytes);
```

##### Format of the returned value from `WC3ReplayParser::parse`:
```perl
{
    game => {
        creator   => <string>,
        duration  => <number>,
        is_public => <boolean>,
        name      => <string>,
        speed     => <string>,
        type      => <string>,
        version   => <string>,
    },

    map => {
        advanced_settings => {
            full_shared_unit_control => <boolean>,
            lock_teams               => <boolean>,
            observer                 => <string>,
            random_hero              => <boolean>,
            random_races             => <boolean>,
            teams_together           => <boolean>,
            visibility               => <string>,
        },
        dirname                      => <string>,
        filename                     => <string>,
        fullpath                     => <string>,
    },

    players => {
        <number: player_id> => {
            id            => <number>,
            name          => <string>,
            team          => <number>,
            left_at       => <number>,
            is_ai         => <boolean>,
            actions_count => <number>,
            color         => <number>,
            handicap      => <number>,
            game_result   => <string>,
            slot_index    => <number>,
            main_race     => <string>,

            build_order => {
                <number: time_in_milliseconds> => {
                    item_id => <string>,
                }
                # other units/buildings/upgrades
                # ...
            },

            items => {
                <string: item_id> => <number: item count>,
                # other items the player's heroes used
                # ...
            },

            heroes      => {
                <string: hero_id> => {
                    <string: ability_id> => <number: level of ability>,
                    # other abilities for this hero
                    # ...
                }
                # other heroes
                # ...
            },
            heroes_order => [
                <string: hero id of the first hero the player trained> ,
                <string: hero id of the second hero the player trained if any>,
                <string: hero id of the third hero the player trained if any>,
            ],

            hotkeys => {
            <number: hotkey> {
                assign                   => <number: of times the hotkey was assigned>,
                number_of_units_in_group => <number>,
                select                   => <number: of times the units in the group were selected via this hotkey>,
                unit_ids                 => [
                    <string: unit_id>,
                    # other units in the group selected via this hotkey
                    # ...
                ],
                }
            },

            race => {
                <string: race name> => {
                    buildings => {
                        <string: building id> => <number: building count>
                        # other buildings
                        # ...
                    },
                    units => {
                        <string: unit id> => <number: unit count>
                        # other units
                        # ...
                    },
                    upgrades => {
                        <string: upgrade id> => <number: upgrade count>
                        # other upgrades
                        # ...
                    },
                },
                # other races =)
                # ...
            },
        },
        # other players
        # ...
    },

    observers => [
        {
            id         => <number>,
            name       => <string>,
            slot_index => 1,
        },
        # other observers
        # ...
    ],

    chat => [
        {
            recipient        => <string>,
            sender_player_id => <number>,
            text             => <string>,
            time             => <number>,
            type             => <string>,
        },
        # more chat messages
        # ...
    ],

    },
}
```

###### An example for the $replay format:
```perl
{
  chat => [
    {
      recipient => "all_players",
      sender_player_id => 2,
      text => "Shortest load by player [iskes] was 3.10 seconds.",
      time => 0,
      type => "normal",
    },
    {
      recipient => "all_players",
      sender_player_id => 2,
      text => "Longest load by player [SteppinRazor] was 5.49 seconds.",
      time => 0,
      type => "normal",
    },
    {
      recipient => "player_3",
      sender_player_id => 2,
      text => "Your load time was 5.11 seconds.",
      time => 0,
      type => "normal",
    },
    {
      recipient => "all_players",
      sender_player_id => 2,
      text => "Make sure to support the FFA Masters League by liking us on Facebook at Facebook.com/FFAMasters ",
      time => 0,
      type => "normal",
    },
    {
      recipient => "all_players",
      sender_player_id => 2,
      text => "Subscribe to our YouTube channel at YouTube.com/FFAMasters!",
      time => 0,
      type => "normal",
    },
    {
      recipient => "all_players",
      sender_player_id => 2,
      text => " ",
      time => 0,
      type => "normal",
    },
    {
      recipient => "all_players",
      sender_player_id => 2,
      text => "Season 18 of the FFA Masters League is now accepting applications at FFAMasters.net",
      time => 0,
      type => "normal",
    },
    {
      recipient => "all_players",
      sender_player_id => 3,
      text => "lol",
      time => 231200,
      type => "normal",
    },
    {
      recipient => "all_players",
      sender_player_id => 4,
      text => "raped",
      time => 234700,
      type => "normal",
    },
    {
      recipient => "all_players",
      sender_player_id => 3,
      text => "quit ",
      time => 238300,
      type => "normal",
    },
    {
      recipient => "all_players",
      sender_player_id => 4,
      text => "leave",
      time => 378700,
      type => "normal",
    },
    {
      recipient => "all_players",
      sender_player_id => 4,
      text => "u lost",
      time => 379600,
      type => "normal",
    },
    {
      recipient => "all_players",
      sender_player_id => 4,
      text => "fluke win",
      time => 381900,
      type => "normal",
    },
    {
      recipient => "all_players",
      sender_player_id => 3,
      text => "yea this was ur right",
      time => 386800,
      type => "normal",
    },
    {
      recipient => "all_players",
      sender_player_id => 3,
      text => 101,
      time => 397500,
      type => "normal",
    },
    {
      recipient => "all_players",
      sender_player_id => 3,
      text => "1-1",
      time => 398100,
      type => "normal",
    },
    {
      recipient => "all_players",
      sender_player_id => 4,
      text => " told u im the better",
      time => 398200,
      type => "normal",
    },
    {
      recipient => "all_players",
      sender_player_id => 2,
      text => "iskes has left the game voluntarily.",
      time => 398700,
      type => "normal",
    },
  ],
  game => {
    creator   => "FML-League",
    duration  => 400750,
    is_public => 1,
    name      => "LWvsSEKSI",
    speed     => "fast",
    type      => "unknown_or_custom_game",
    version   => "TFT",
  },
  map => {
    advanced_settings => {
      full_shared_unit_control => 0,
      lock_teams               => 1,
      observer                 => "full_observers",
      random_hero              => 0,
      random_races             => 0,
      teams_together           => 0,
      visibility               => "default",
    },
    dirname => "Maps\\frozenthrone\\",
    filename => "(4)TurtleRock.w3x",
    fullpath => "Maps\\frozenthrone\\(4)TurtleRock.w3x",
  },
  observers => [
    { id => 2, name => "SteppinRazor", slot_index => 1 },
    { id => 5, name => "FFA_Wuffle", slot_index => 4 },
  ],
  players => {
    3 => {
           actions_count => 1527,
           build_order => {
             2100   => { item_id => "uaco" },
             5100   => { item_id => "uaod" },
             7400   => { item_id => "uzig" },
             18300  => { item_id => "uaco" },
             37900  => { item_id => "usep" },
             48800  => { item_id => "uaco" },
             49000  => { item_id => "uaco" },
             65100  => { item_id => "utom" },
             67000  => { item_id => "Udea" },
             86300  => { item_id => "ugrv" },
             98500  => { item_id => "ugho" },
             98600  => { item_id => "ugho" },
             112300 => { item_id => "ugho" },
             140300 => { item_id => "uzig" },
             153200 => { item_id => "uzg2" },
             182900 => { item_id => "uzig" },
             198200 => { item_id => "uaco" },
             198300 => { item_id => "uaco" },
             198500 => { item_id => "uaco" },
             218900 => { item_id => "uaco" },
             219100 => { item_id => "uaco" },
             248000 => { item_id => "uaco" },
             260600 => { item_id => "uaco" },
             285900 => { item_id => "uaco" },
             306500 => { item_id => "uaco" },
             306600 => { item_id => "uaco" },
             333500 => { item_id => "uaco" },
             355400 => { item_id => "uzig" },
           },
           color => 10,
           game_result => "defeat",
           handicap => 100,
           heroes => { Udea => { AUau => 1, AUdc => 2 } },
           heroes_order => ["Udea"],
           hotkeys => {
             1 => {
                    assign => 8,
                    number_of_units_in_group => 11,
                    unit_ids => [
                      15465,
                      14358,
                      15066,
                      15277,
                      15420,
                      16046,
                      16754,
                      16793,
                      17183,
                      17228,
                      17298,
                    ],
                  },
             2 => {
                    assign => 8,
                    number_of_units_in_group => 1,
                    select => 14,
                    unit_ids => [16390],
                  },
             3 => {
                    assign => 43,
                    number_of_units_in_group => 1,
                    select => 12,
                    unit_ids => [16489],
                  },
             4 => {
                    assign => 72,
                    number_of_units_in_group => 1,
                    select => 26,
                    unit_ids => [15616],
                  },
             5 => {
                    assign => 91,
                    number_of_units_in_group => 1,
                    select => 27,
                    unit_ids => [16649],
                  },
           },
           id => 3,
           is_ai => 0,
           items => { rnec => 1 },
           left_at => 398700,
           main_race => "undead",
           name => "iskes",
           race => {
             undead => {
               buildings => { uaod => 1, ugrv => 1, usep => 1, utom => 1, uzg2 => 1, uzig => 4 },
               units => { uaco => 15, ugho => 3 },
             },
           },
           slot_index => 2,
           team => 1,
         },
    4 => {
           actions_count => 1836,
           build_order => {
             2500   => { item_id => "hpea" },
             2700   => { item_id => "hpea" },
             6000   => { item_id => "halt" },
             11100  => { item_id => "hhou" },
             19600  => { item_id => "hbar" },
             28100  => { item_id => "hpea" },
             34900  => { item_id => "hpea" },
             48100  => { item_id => "hpea" },
             63600  => { item_id => "hhou" },
             69500  => { item_id => "Hamg" },
             74000  => { item_id => "hpea" },
             80500  => { item_id => "hfoo" },
             100400 => { item_id => "hpea" },
             101100 => { item_id => "hfoo" },
             103100 => { item_id => "hwtw" },
             113400 => { item_id => "hpea" },
             115300 => { item_id => "hhou" },
             128100 => { item_id => "hfoo" },
             132700 => { item_id => "hatw" },
             155700 => { item_id => "hfoo" },
             157600 => { item_id => "hpea" },
             177800 => { item_id => "hfoo" },
             181700 => { item_id => "hhou" },
             194300 => { item_id => "hfoo" },
             204200 => { item_id => "hfoo" },
             223400 => { item_id => "hfoo" },
             228500 => { item_id => "hfoo" },
             248500 => { item_id => "hfoo" },
             257900 => { item_id => "hpea" },
             267700 => { item_id => "hfoo" },
             293900 => { item_id => "hfoo" },
             294600 => { item_id => "hpea" },
             294800 => { item_id => "hpea" },
             322000 => { item_id => "hwtw" },
             323100 => { item_id => "hfoo" },
             333000 => { item_id => "hfoo" },
             333600 => { item_id => "hpea" },
             349600 => { item_id => "hfoo" },
             363300 => { item_id => "hatw" },
             365700 => { item_id => "hfoo" },
           },
           color => 2,
           game_result => "victory",
           handicap => 100,
           heroes => { Hamg => { AHab => 1, AHwe => 1 } },
           heroes_order => ["Hamg"],
           hotkeys => {
             2 => {
                    assign => 9,
                    number_of_units_in_group => 4,
                    select => 33,
                    unit_ids => [13321, 15521, 16791, 17308],
                  },
             3 => {
                    assign => 11,
                    number_of_units_in_group => 5,
                    select => 62,
                    unit_ids => [15158, 15184, 15440, 17275, 15842],
                  },
             6 => {
                    assign => 4,
                    number_of_units_in_group => 1,
                    select => 134,
                    unit_ids => [16641],
                  },
             7 => {
                    assign => 4,
                    number_of_units_in_group => 1,
                    select => 112,
                    unit_ids => [12946],
                  },
             8 => {
                    assign => 4,
                    number_of_units_in_group => 1,
                    select => 27,
                    unit_ids => [16856],
                  },
           },
           id => 4,
           is_ai => 0,
           left_at => 400750,
           main_race => "random",
           name => "L1ghtweight",
           race => {
             human => {
               buildings => { halt => 1, hatw => 2, hbar => 1, hhou => 4, hwtw => 2 },
               units => { hfoo => 16, hpea => 13 },
             },
           },
           slot_index => 3,
           team => 2,
         },
  },
}
```