import 'package:flutter_test/flutter_test.dart';
import 'package:vote_smart/services/voting_service.dart';

void main() {
  group('VotingService Tests', () {
    group('First Past The Post', () {
      test('Basic voting scenario with weights', () {
        final votes = [
          {'choice': 'approve', 'weight': 1.0},
          {'choice': 'approve', 'weight': 2.0},
          {'choice': 'reject', 'weight': 1.0},
          {'choice': 'approve', 'weight': 0.5},
        ];

        final results = VotingService.calculateFirstPastThePost(votes);

        expect(results['totalVotes'], equals(4));
        expect(results['counts']['approve'], equals(3.5));
        expect(results['counts']['reject'], equals(1.0));
        expect(results['winner'], equals('approve'));
      });

      test('Tie scenario with weights', () {
        final votes = [
          {'choice': 'approve', 'weight': 1.5},
          {'choice': 'reject', 'weight': 1.5},
          {'choice': 'approve', 'weight': 1.0},
          {'choice': 'reject', 'weight': 1.0},
        ];

        final results = VotingService.calculateFirstPastThePost(votes);

        expect(results['totalVotes'], equals(4));
        expect(results['counts']['approve'], equals(2.5));
        expect(results['counts']['reject'], equals(2.5));
        // In a tie, the first option with max votes is chosen
        expect(results['winner'], equals('approve'));
      });

      test('Empty votes', () {
        final votes = <Map<String, dynamic>>[];

        final results = VotingService.calculateFirstPastThePost(votes);

        expect(results['totalVotes'], equals(0));
        expect(results['counts'], isEmpty);
        expect(results['winner'], isNull);
      });

      test('Invalid vote format with weights', () {
        final votes = [
          {'choice': 'approve', 'weight': 1.0},
          {'choice': null, 'weight': 1.0}, // choice is null, weight won't apply to a specific option
          {'wrong_key': 'reject', 'weight': 1.0}, // no 'choice' key
          {'choice': 123, 'weight': 1.0}, // Wrong choice type
        ];

        final results = VotingService.calculateFirstPastThePost(votes);

        expect(results['totalVotes'], equals(4)); // Still 4 vote objects processed
        expect(results['counts']['approve'], equals(1.0)); // Only the valid vote is counted with its weight
        expect(results['counts'].length, equals(1)); // Only 'approve' should have a count
        expect(results['winner'], equals('approve'));
      });

      test('Scenario with zero weights', () {
        final votes = [
          {'choice': 'approve', 'weight': 0.0},
          {'choice': 'reject', 'weight': 0.0},
          {'choice': 'neutral', 'weight': 0.0},
        ];
        final results = VotingService.calculateFirstPastThePost(votes);
        expect(results['totalVotes'], equals(3));
        expect(results['counts']['approve'], equals(0.0));
        expect(results['counts']['reject'], equals(0.0));
        expect(results['counts']['neutral'], equals(0.0));
        // Winner is the first one encountered in a 0-0-0 tie
        expect(results['winner'], equals('approve')); 
      });

      test('Scenario with mixed valid and zero weights', () {
        final votes = [
          {'choice': 'approve', 'weight': 2.0},
          {'choice': 'reject', 'weight': 0.0},
          {'choice': 'approve', 'weight': 0.0},
          {'choice': 'neutral', 'weight': 1.5},
        ];
        final results = VotingService.calculateFirstPastThePost(votes);
        expect(results['totalVotes'], equals(4));
        expect(results['counts']['approve'], equals(2.0));
        expect(results['counts']['reject'], equals(0.0));
        expect(results['counts']['neutral'], equals(1.5));
        expect(results['winner'], equals('approve'));
      });
    });

    group('Approval Voting', () {
      test('Basic approval scenario with weights', () {
        final votes = [
          {'choice': ['apple', 'banana'], 'weight': 1.0},
          {'choice': ['apple', 'orange'], 'weight': 2.0},
          {'choice': ['banana'], 'weight': 0.5},
        ];
        final results = VotingService.calculateApprovalVoting(votes);
        expect(results['totalVotes'], equals(3));
        expect(results['counts']['apple'], equals(3.0));
        expect(results['counts']['banana'], equals(1.5));
        expect(results['counts']['orange'], equals(2.0));
        expect(results['winner'], equals('apple'));
      });

      test('Approval tie scenario with weights', () {
        final votes = [
          {'choice': ['apple', 'banana'], 'weight': 1.0},
          {'choice': ['orange'], 'weight': 2.0},
          {'choice': ['pear'], 'weight': 2.0},
        ];
        final results = VotingService.calculateApprovalVoting(votes);
        expect(results['totalVotes'], equals(3));
        expect(results['counts']['apple'], equals(1.0));
        expect(results['counts']['banana'], equals(1.0));
        expect(results['counts']['orange'], equals(2.0));
        expect(results['counts']['pear'], equals(2.0));
        expect(results['winner'], equals('orange')); // First one with max votes
      });

      test('Approval with empty votes list', () {
        final votes = <Map<String, dynamic>>[];
        final results = VotingService.calculateApprovalVoting(votes);
        expect(results['totalVotes'], equals(0));
        expect(results['counts'], isEmpty);
        expect(results['winner'], isNull);
      });

      test('Approval with invalid/empty choice types and weights', () {
        final votes = [
          {'choice': ['apple'], 'weight': 1.0},
          {'choice': [123, 'banana'], 'weight': 1.0}, // invalid type in list
          {'choice': 'orange', 'weight': 1.0},      // not a list, should be skipped by current logic
          {'choice': [], 'weight': 0.5},            // empty list of choices
          {'choice': ['apple', 'cherry'], 'weight': 0.0} // zero weight
        ];
        final results = VotingService.calculateApprovalVoting(votes);
        expect(results['totalVotes'], equals(5)); 
        expect(results['counts']['apple'], equals(1.0)); // 1.0 from first vote, 0.0 from last
        expect(results['counts']['banana'], equals(1.0));
        expect(results['counts']['cherry'], equals(0.0));
        expect(results['counts']['orange'], isNull); // Not added if choice is not a list
        expect(results['winner'], equals('apple')); // or banana, assuming apple comes first in iteration
      });
    });

    group('Majority Runoff', () {
      test('Majority achieved in first round with weights', () {
        final votes = [
          {'choice': 'A', 'weight': 3.0},
          {'choice': 'B', 'weight': 1.5},
          {'choice': 'C', 'weight': 1.0},
        ];
        // Total weighted votes = 3.0 + 1.5 + 1.0 = 5.5
        // Majority threshold = 5.5 / 2 = 2.75
        // 'A' has 3.0, which is > 2.75
        final results = VotingService.calculateMajorityRunoff(votes);
        expect(results['winner'], equals('A'));
        expect(results['majorityAchieved'], isTrue);
        expect(results['runoffNeeded'], isFalse);
        expect(results['round'], equals(1));
        expect(results['counts']['A'], equals(3.0));
        expect(results['totalVotes'], equals(5.5));
      });

      test('Runoff needed and winner determined with weights', () {
        final votes = [
          {'choice': 'A', 'weight': 2.0}, // Round 1: A=2.0
          {'choice': 'B', 'weight': 2.5}, // Round 1: B=2.5
          {'choice': 'C', 'weight': 1.0}, // Round 1: C=1.0
        ];
        // Total weighted votes R1 = 2.0 + 2.5 + 1.0 = 5.5. Majority > 2.75. No one has it.
        // Runoff between B (2.5) and A (2.0).
        // Assuming runoff considers original votes for B or A:
        // B gets 2.5, A gets 2.0. B wins.
        final results = VotingService.calculateMajorityRunoff(votes);
        expect(results['winner'], equals('B'));
        expect(results['majorityAchieved'], isFalse); // For round 1
        expect(results['runoffNeeded'], isTrue);
        expect(results['round'], equals(2));
        expect(results['round1Counts']['A'], equals(2.0));
        expect(results['round1Counts']['B'], equals(2.5));
        expect(results['round1Counts']['C'], equals(1.0));
        expect(results['totalVotesRound1'], equals(5.5));
        expect(results['runoffCounts']?['A'], equals(2.0));
        expect(results['runoffCounts']?['B'], equals(2.5));
        // Total runoff weighted votes only include those for top 2
        expect(results['totalVotesRunoff'], equals(4.5)); 
      });

      test('Majority Runoff with empty votes list', () {
        final votes = <Map<String, dynamic>>[];
        final results = VotingService.calculateMajorityRunoff(votes);
        expect(results['winner'], isNull);
        expect(results['majorityAchieved'], isFalse);
        expect(results['runoffNeeded'], isFalse);
        expect(results['counts'], isEmpty);
        expect(results['totalVotes'], equals(0.0));
        expect(results['message'], equals('No weighted votes cast.'));
      });

      test('Majority Runoff with only one candidate receiving votes', () {
        final votes = [
          {'choice': 'A', 'weight': 2.0},
          {'choice': 'A', 'weight': 1.0},
        ];
        // Total weighted: 3.0. Majority > 1.5. A has 3.0.
        final results = VotingService.calculateMajorityRunoff(votes);
        expect(results['winner'], equals('A'));
        expect(results['majorityAchieved'], isTrue); // Achieves >50% of total weighted votes
        expect(results['runoffNeeded'], isFalse);
        expect(results['round'], equals(1));
        expect(results['counts']['A'], equals(3.0));
        expect(results['totalVotes'], equals(3.0));
      });

      test('Majority Runoff - Insufficient distinct candidates for runoff (e.g. all vote for one)', () {
        final votes = [
          {'choice': 'A', 'weight': 0.4}, // Does not meet >50% if this is the only vote type
        ];
         // Total weighted: 0.4. Majority > 0.2. A has 0.4.
        final results = VotingService.calculateMajorityRunoff(votes);
        expect(results['winner'], equals('A'));
        expect(results['majorityAchieved'], isTrue); 
        expect(results['runoffNeeded'], isFalse);
        expect(results['round'], equals(1));
      });

      test('Majority Runoff - Tie in runoff, winner from round 1 ranking', () {
        final testVotesRunoffTie = [
            {'choice': 'CandidateA', 'weight': 3.0},
            {'choice': 'CandidateB', 'weight': 3.0},
            {'choice': 'CandidateC', 'weight': 2.0},
        ];
        // R1: A=3, B=3, C=2. Total R1=8. Maj>4. No one. Runoff A, B.
        // Runoff counts: A=3, B=3. Tie. Winner should be A.
        final results = VotingService.calculateMajorityRunoff(testVotesRunoffTie);
        expect(results['winner'], equals('CandidateA'));
        expect(results['majorityAchieved'], isFalse); 
        expect(results['runoffNeeded'], isTrue);
        expect(results['round'], equals(2));
        expect(results['round1Counts']['CandidateA'], equals(3.0));
        expect(results['round1Counts']['CandidateB'], equals(3.0));
        expect(results['runoffCounts']?['CandidateA'], equals(3.0));
        expect(results['runoffCounts']?['CandidateB'], equals(3.0));
      });

    });

    group('Weight Voting (Ranked Choice by Weight Sum)', () {
      test('Basic weight voting scenario', () {
        final votes = [
          {'choice': 'Alice', 'weight': 100.0},
          {'choice': 'Bob', 'weight': 200.0},
          {'choice': 'Charlie', 'weight': 50.0},
        ];
        final results = VotingService.calculateWeightVoting(votes);
        expect(results['winner'], equals('Bob'));
        expect(results['counts']['Alice'], equals(100.0));
        expect(results['counts']['Bob'], equals(200.0));
        expect(results['counts']['Charlie'], equals(50.0));
        expect(results['totalWeight'], equals(350.0));
      });

      test('Weight voting with tie, first one wins', () {
        final votes = [
          {'choice': 'Alice', 'weight': 200.0},
          {'choice': 'Bob', 'weight': 200.0},
          {'choice': 'Charlie', 'weight': 50.0},
        ];
        final results = VotingService.calculateWeightVoting(votes);
        expect(results['winner'], equals('Alice'));
        expect(results['counts']['Alice'], equals(200.0));
        expect(results['counts']['Bob'], equals(200.0));
        expect(results['counts']['Charlie'], equals(50.0));
        expect(results['totalWeight'], equals(450.0));
      });

      test('Weight voting with empty votes list', () {
        final votes = <Map<String, dynamic>>[];
        final results = VotingService.calculateWeightVoting(votes);
        expect(results['winner'], isNull);
        expect(results['counts'], isEmpty);
        expect(results['totalWeight'], equals(0.0));
        expect(results['message'], contains('No weighted votes cast'));
      });

       test('Weight voting with all zero weights', () {
        final votes = [
          {'choice': 'Alice', 'weight': 0.0},
          {'choice': 'Bob', 'weight': 0.0},
        ];
        final results = VotingService.calculateWeightVoting(votes);
        expect(results['winner'], equals('Alice')); // First one in 0-0 tie
        expect(results['counts']['Alice'], equals(0.0));
        expect(results['counts']['Bob'], equals(0.0));
        expect(results['totalWeight'], equals(0.0));
      });

      test('Weight voting with mixed non-zero and zero weights', () {
        final votes = [
          {'choice': 'Alice', 'weight': 10.0},
          {'choice': 'Bob', 'weight': 0.0},
          {'choice': 'Charlie', 'weight': 5.0},
        ];
        final results = VotingService.calculateWeightVoting(votes);
        expect(results['winner'], equals('Alice'));
        expect(results['counts']['Alice'], equals(10.0));
        expect(results['counts']['Bob'], equals(0.0));
        expect(results['counts']['Charlie'], equals(5.0));
        expect(results['totalWeight'], equals(15.0));
      });
    });
  });

  group('Schulze Method', () {
    test('Basic Condorcet winner scenario', () {
      // A is preferred over B and C by all voters
      final votes = [
        {
          'choice': {'A': 1, 'B': 2, 'C': 3},
          'weight': 1.0
        },
        {
          'choice': {'A': 1, 'B': 3, 'C': 2},
          'weight': 1.0
        },
        {
          'choice': {'A': 1, 'B': 2, 'C': 3},
          'weight': 1.0
        },
      ];

      final results = VotingService.calculateSchulze(votes);

      expect(results['winner'], equals('A'));
      expect(List.from(results['ranking']), equals(['A', 'B', 'C']));
      expect(results['totalVotes'], equals(3));
      
      // Verify pairwise preferences
      final pairwise = results['pairwisePreferences'] as Map<String, dynamic>;
      expect(pairwise['A']?['B'], equals(3.0)); // A > B in all 3 votes
      expect(pairwise['A']?['C'], equals(3.0)); // A > C in all 3 votes
      expect(pairwise['B']?['A'], equals(0.0)); // B > A in 0 votes
      
      // Verify strongest paths
      final paths = results['strongestPaths'] as Map<String, dynamic>;
      expect(paths['A']?['B'], equals(3.0));
      expect(paths['A']?['C'], equals(3.0));
    });

    test('No Condorcet winner (cycle) scenario', () {
      // A > B > C > A (cycle)
      final votes = [
        {'choice': {'A': 1, 'B': 2, 'C': 3}, 'weight': 1.0}, // A > B > C
        {'choice': {'B': 1, 'C': 2, 'A': 3}, 'weight': 1.0}, // B > C > A
        {'choice': {'C': 1, 'A': 2, 'B': 3}, 'weight': 1.0}, // C > A > B
      ];

      final results = VotingService.calculateSchulze(votes);
      
      // In this cycle, Schulze should still pick a winner based on path strengths
      expect(['A', 'B', 'C'].contains(results['winner']), isTrue);
      expect(results['ranking'].length, equals(3));
      expect(
          (results['ranking'] as List).toSet(),
          equals({'A', 'B', 'C'}));
      expect(results['totalVotes'], equals(3));
      
      // Verify pairwise preferences show the cycle
      final pairwise = results['pairwisePreferences'] as Map<String, dynamic>;
      expect(pairwise['A']?['B'], equals(2.0)); // A > B in 2 out of 3
      expect(pairwise['B']?['C'], equals(2.0)); // B > C in 2 out of 3
      expect(pairwise['C']?['A'], equals(2.0)); // C > A in 2 out of 3
    });

    test('Weighted votes scenario', () {
      // With weights, some voters count more than others
      final votes = [
        {'choice': {'A': 1, 'B': 2}, 'weight': 2.0}, // A > B (counts as 2 votes)
        {'choice': {'B': 1, 'A': 2}, 'weight': 1.0}, // B > A (counts as 1 vote)
      ];

      final results = VotingService.calculateSchulze(votes);
      
      // A should win because it has 2.0 weight vs B's 1.0
      expect(results['winner'], equals('A'));
      expect(List.from(results['ranking']), equals(['A', 'B']));
      
      // Verify pairwise preferences with weights
      final pairwise = results['pairwisePreferences'] as Map<String, dynamic>;
      expect(pairwise['A']?['B'], equals(2.0)); // A > B with weight 2.0
      expect(pairwise['B']?['A'], equals(1.0)); // B > A with weight 1.0
    });

    test('Tie scenario', () {
      // Perfect tie between A and B
      final votes = [
        {'choice': {'A': 1, 'B': 2}, 'weight': 1.0},
        {'choice': {'B': 1, 'A': 2}, 'weight': 1.0},
      ];

      final results = VotingService.calculateSchulze(votes);
      
      // In a tie, the method should still return a winner (implementation defined which one)
      expect(['A', 'B'].contains(results['winner']), isTrue);
      expect((results['ranking'] as List).length, equals(2));
      expect((results['ranking'] as List).toSet(), equals({'A', 'B'}));
      
      // Verify pairwise preferences show the tie
      final pairwise = results['pairwisePreferences'] as Map<String, dynamic>;
      expect(pairwise['A']?['B'], equals(1.0));
      expect(pairwise['B']?['A'], equals(1.0));
    });

    test('Empty votes list', () {
      final votes = <Map<String, dynamic>>[];
      final results = VotingService.calculateSchulze(votes);
      
      expect(results['winner'], isNull);
      expect(results['ranking'], isEmpty);
      expect(results['totalVotes'], equals(0));
      expect(results['pairwisePreferences'], isEmpty);
      expect(results['strongestPaths'], isEmpty);
    });

    test('Single candidate', () {
      final votes = [
        {'choice': {'A': 1}, 'weight': 1.0},
      ];

      final results = VotingService.calculateSchulze(votes);
      
      expect(results['winner'], equals('A'));
      expect(List.from(results['ranking']), equals(['A']));
      expect(results['totalVotes'], equals(1));
      expect((results['pairwisePreferences'] as Map).length, equals(1));
      expect((results['strongestPaths'] as Map).length, equals(1));
    });

    test('Complex scenario with multiple candidates', () {
      // More complex scenario with 5 candidates
      final votes = [
        {'choice': {'A': 1, 'B': 2, 'C': 3, 'D': 4, 'E': 5}, 'weight': 1.0},
        {'choice': {'A': 1, 'B': 2, 'C': 3, 'D': 4, 'E': 5}, 'weight': 1.0},
        {'choice': {'B': 1, 'C': 2, 'A': 3, 'E': 4, 'D': 5}, 'weight': 1.0},
        {'choice': {'C': 1, 'D': 2, 'E': 3, 'B': 4, 'A': 5}, 'weight': 1.0},
        {'choice': {'D': 1, 'E': 2, 'C': 3, 'B': 4, 'A': 5}, 'weight': 1.5},
      ];

      final results = VotingService.calculateSchulze(votes);
      
      // The exact winner depends on the Schulze method calculations
      // We'll just verify the structure and that we get a valid result
      expect(['A', 'B', 'C', 'D', 'E'].contains(results['winner']), isTrue);
      expect((results['ranking'] as List).length, equals(5));
      expect(
          (results['ranking'] as List).toSet(),
          equals({'A', 'B', 'C', 'D', 'E'}));
      expect(results['totalVotes'], equals(5.5)); // 1+1+1+1+1.5
      
      // Verify pairwise preferences are calculated
      final pairwise = results['pairwisePreferences'] as Map<String, dynamic>;
      expect(pairwise['A']?['B'], greaterThanOrEqualTo(0.0));
      expect(pairwise['B']?['A'], greaterThanOrEqualTo(0.0));
      
      // Verify strongest paths are at least as strong as direct preferences
      final paths = results['strongestPaths'] as Map<String, dynamic>;
      expect(paths['A']?['B'], greaterThanOrEqualTo(pairwise['A']?['B'] ?? 0.0));
    });
  });
}
