import 'package:logger/logger.dart';
import '../models/data_models.dart';
import './delegation_service.dart';
import './audit_service.dart';
import '../models/audit_model.dart';

final _logger = Logger();

/// VotingService provides implementations of various voting methods.
///
/// Implementation Status:
/// COMPLETED: First Past The Post (Sprint 1)
/// COMPLETED: Approval Voting (Sprint 2)
/// COMPLETED: Majority Runoff (Sprint 2)
/// PROTOTYPE: All other voting methods (Future Sprints)
///
/// This service contains both fully implemented and tested voting methods
/// as well as prototype implementations for future development.

class VotingService {
  /// Calculate results based on voting method.
  ///
  /// This is the main entry point for calculating voting results.
  /// It dispatches to the appropriate calculation method based on the voting method.
  ///
  /// Implementation Status:
  /// - First Past The Post: COMPLETED (Sprint 1)
  /// - Approval Voting: COMPLETED (Sprint 2)
  /// - Majority Runoff: COMPLETED (Sprint 2)
  /// - All other methods: PROTOTYPE (Future Sprints)
  static Future<Map<String, dynamic>> calculateResults(
      VotingMethod method,
      List<Map<String, dynamic>> initialVotes,
      DelegationService delegationService,
      String proposalId) async {
    final auditService = AuditService();
    Map<String, WeightedPropagatedVote> allEffectiveVotes = {};

    final Map<String, VoteModel> allVotesMap = {};
    for (var voteData in initialVotes) {
      final vote = VoteModel.fromJson(voteData);
      allVotesMap[vote.userId] = vote;
      _logger.i(
          'Vote cast by ${vote.userId}: ${vote.choice} with weight ${vote.weight}');
      await auditService.logAuditEvent(
        eventType: AuditEventType.VOTE_CAST,
        actorUserId: vote.userId,
        entityId: proposalId,
        entityType: 'PROPOSAL',
        details: {
          'choice': vote.choice,
          'isDirectVote': true,
          'weight': vote.weight,
        },
      );
    }

    final Map<String, List<DelegationModel>> allDelegationsMap =
        {}; // Placeholder for actual delegations

    // Propagate votes through delegations for each initial vote
    for (var vote in allVotesMap.values) {
      final voterId = vote.userId;
      final proposalId = vote.proposalId;
      // final topicId = vote.topicId; // Use vote's topicId if available
      // Use vote.topicId directly, no need to re-declare

      // Log the initial vote cast event
      auditService.logAuditEvent(
        eventType: AuditEventType.VOTE_CAST,
        actorUserId: voterId,
        entityId: proposalId,
        entityType: 'PROPOSAL',
        details: {
          'choice':
              vote.choice.toString(), // Convert choice to string for logging
          'weight':
              vote.weight, // No longer needs ?? 1.0 as weight is non-nullable
          'topicId': vote.topicId, // Log the topicId used for propagation
        },
      );

      _logger.d(
          'Propagating vote for user: $voterId, proposal: $proposalId, topic: ${vote.topicId}');
      final WeightedPropagatedVote? finalWeightedVote =
          await delegationService.propagateVote(
        voterId,
        proposalId,
        allVotesMap,
        allDelegationsMap, // Pass the correctly typed, though currently empty, map
        vote.choice,
        vote.weight,
        vote.topicId, // Pass topicId from the vote model
      );

      if (finalWeightedVote != null) {
        // The userId in finalWeightedVote.vote is the user whose vote this effectively is
        // (could be voterId themselves or a delegatee).
        // The vote choice is finalWeightedVote.vote.vote.

        // If allEffectiveVotes already contains this user, the one from propagateVote should be authoritative
        // as it has considered direct votes and weighted delegation paths.
        _logger.i(
            'Effective vote for user ${finalWeightedVote.vote.userId} via propagation (initiated by $voterId) is ${finalWeightedVote.vote.vote} with weight ${finalWeightedVote.effectiveWeight}. Original voter: ${finalWeightedVote.vote.originalVoter}');
        allEffectiveVotes[finalWeightedVote.vote.userId] = finalWeightedVote;

        // Log the vote propagation event
        await auditService.logAuditEvent(
          eventType: AuditEventType.VOTE_PROPAGATED,
          actorUserId: finalWeightedVote
              .vote.originalVoterId, // The user who initiated the chain
          targetUserId: finalWeightedVote
              .vote.userId, // User whose vote this effectively is
          entityId: proposalId,
          entityType: 'PROPOSAL',
          details: {
            'finalChoice': finalWeightedVote.vote.vote.toString(),
            'effectiveWeight': finalWeightedVote.effectiveWeight,
            'delegationPath':
                finalWeightedVote.vote.delegationPath, // Corrected path access
            'originalVoteWeight': finalWeightedVote
                .vote.weight, // Weight of the vote at its source
            'topicId': finalWeightedVote.vote.topicId,
          },
        );
      } else {
        _logger.i(
            'No effective vote determined for $voterId after propagation (may have delegated without final recipient voting, or cycle detected).');
      }
    }

    // At this point, allEffectiveVotes contains the final set of votes after propagation.
    // Convert Map<String, VoteModel> to List<Map<String, dynamic>> for calculation methods
    final List<Map<String, dynamic>> effectiveVotesForCalculation =
        allEffectiveVotes.values
            .map((wpv) =>
                wpv.vote.toJson(effectiveWeightOverride: wpv.effectiveWeight))
            .toList();

    // Now, proceed with the specific voting method calculation
    switch (method) {
      case VotingMethod.firstPastThePost:
        return calculateFirstPastThePost(effectiveVotesForCalculation);
      case VotingMethod.approvalVoting:
        return calculateApprovalVoting(effectiveVotesForCalculation);
      case VotingMethod.majorityRunoff:
        return calculateMajorityRunoff(effectiveVotesForCalculation);
      case VotingMethod.schulze:
        return calculateSchulze(effectiveVotesForCalculation);
      case VotingMethod.instantRunoff:
        return calculateInstantRunoff(effectiveVotesForCalculation);
      case VotingMethod.starVoting:
        return calculateStarVoting(effectiveVotesForCalculation);
      case VotingMethod.rangeVoting:
        return calculateRangeVoting(effectiveVotesForCalculation);
      case VotingMethod.majorityJudgment:
        return calculateMajorityJudgment(effectiveVotesForCalculation);
      case VotingMethod.quadraticVoting:
        return calculateQuadraticVoting(effectiveVotesForCalculation);
      case VotingMethod.condorcet:
        return calculateCondorcet(effectiveVotesForCalculation);
      case VotingMethod.bordaCount:
        return calculateBordaCount(effectiveVotesForCalculation);
      case VotingMethod.cumulativeVoting:
        return calculateCumulativeVoting(effectiveVotesForCalculation);
      case VotingMethod.kemenyYoung:
        return calculateKemenyYoung(effectiveVotesForCalculation);
      case VotingMethod.dualChoice:
        return calculateDualChoice(effectiveVotesForCalculation);
      case VotingMethod.weightVoting:
        return calculateWeightVoting(effectiveVotesForCalculation);
    }
  }



  /// First Past The Post: Winner is the option with the most votes.
  ///
  /// Status: COMPLETED (Sprint 1)
  ///
  /// This method implements the First Past The Post voting system where
  /// each voter selects a single option, and the option with the most votes wins.
  ///
  /// Test Coverage: Full test suite available in voting_service_test.dart
  static Map<String, dynamic> calculateFirstPastThePost(
      List<Map<String, dynamic>> votes) {
    Map<String, double> counts = {}; // Use double for weighted counts

    // Count votes for each option, applying weights
    for (var vote in votes) {
      final choice = vote['choice'];
      final weight = (vote['weight'] as num?)?.toDouble() ??
          1.0; // Get weight, default to 1.0

      if (choice != null && choice is String) {
        counts[choice] = (counts[choice] ?? 0.0) + weight;
      }
    }

    // Find winner
    String? winner;
    double maxVotes =
        -1.0; // Initialize to handle all non-negative counts, including 0
    counts.forEach((option, count) {
      if (count > maxVotes) {
        maxVotes = count;
        winner = option;
      }
    });

    return {
      "counts": counts,
      "winner": winner,
      "totalVotes": votes.length,
    };
  }

  /// Approval Voting: Winner is the option with the most approvals.
  ///
  /// Status: COMPLETED (Sprint 2)
  ///
  /// This method implements the Approval Voting system where each voter can
  /// select multiple options they approve of, and the option with the most
  /// approvals wins.
  ///
  /// Test Coverage: Full test suite available in approval_voting_test.dart
  static Map<String, dynamic> calculateApprovalVoting(
      List<Map<String, dynamic>> votes) {
    Map<String, double> counts = {}; // Use double for weighted counts

    // Count approvals for each option, applying weights
    for (var vote in votes) {
      final dynamic choiceValue = vote['choice'];
      final weight = (vote['weight'] as num?)?.toDouble() ??
          1.0; // Get weight, default to 1.0

      if (choiceValue is List) {
        for (var choice in choiceValue) {
          if (choice is String) {
            counts[choice] = (counts[choice] ?? 0.0) + weight;
          }
        }
      }
    }

    // Find winner
    String? winner;
    double maxVotes = 0.0; // Use double for maxVotes
    counts.forEach((option, count) {
      if (count > maxVotes) {
        maxVotes = count;
        winner = option;
      }
    });

    return {
      "counts": counts,
      "winner": winner,
      "totalVotes": votes.length,
    };
  }

  /// Majority Runoff: Winner must have a majority, otherwise top two go to runoff.
  ///
  /// Status: COMPLETED (Sprint 2)
  ///
  /// This method implements the Two-Round System (Majority Runoff) where a candidate
  /// must receive a majority of votes to win. If no candidate receives a majority,
  /// a runoff is held between the top two candidates.
  ///
  /// Test Coverage: Full test suite available in majority_runoff_test.dart
  static Map<String, dynamic> calculateMajorityRunoff(
      List<Map<String, dynamic>> votes) {
    Map<String, double> counts = {}; // Use double for weighted counts
    double totalWeightedVotes = 0.0;

    // Count votes for each option, applying weights
    for (var vote in votes) {
      final choice = vote['choice'];
      final weight = (vote['weight'] as num?)?.toDouble() ??
          1.0; // Get weight, default to 1.0
      if (choice != null && choice is String) {
        counts[choice] = (counts[choice] ?? 0.0) + weight;
      }
    }

    // Determine total weighted votes
    counts.forEach((option, count) {
      totalWeightedVotes += count;
    });

    if (totalWeightedVotes == 0) {
      return {
        "counts": counts,
        "winner": null,
        "majorityAchieved": false,
        "runoffNeeded": false,
        "totalVotes": 0.0,
        "message": "No weighted votes cast."
      };
    }

    // Find top candidates based on weighted counts
    List<MapEntry<String, double>> sortedResults = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Check if there's a majority winner in the first round
    if (sortedResults.isNotEmpty &&
        sortedResults[0].value > totalWeightedVotes / 2) {
      return {
        "counts": counts, // Weighted counts from round 1
        "winner": sortedResults[0].key,
        "majorityAchieved": true,
        "runoffNeeded": false,
        "totalVotes": totalWeightedVotes,
        "round": 1
      };
    }

    // If no majority, proceed to runoff (if possible)
    if (sortedResults.length < 2) {
      // Not enough candidates for a runoff (e.g., only one candidate, or tied for first with no others)
      // The winner is the top candidate, even without majority, as no runoff is possible.
      return {
        "counts": counts, // Weighted counts from round 1
        "winner": sortedResults.isNotEmpty ? sortedResults[0].key : null,
        "majorityAchieved":
            false, // Could still be false if only one candidate didn't get >50%
        "runoffNeeded": false,
        "totalVotes": totalWeightedVotes,
        "message": sortedResults.length == 1
            ? "Only one candidate with votes, wins by default without majority in runoff context."
            : "Not enough distinct candidates for a runoff.",
        "round": 1
      };
    }

    // Runoff between top two based on weighted votes
    String top1 = sortedResults[0].key;
    String top2 = sortedResults[1].key;
    Map<String, double> runoffCounts = {
      top1: 0.0,
      top2: 0.0
    }; // Initialize for weighted runoff counts
    double totalRunoffWeightedVotes = 0.0;

    for (var vote in votes) {
      final choice = vote['choice'];
      final weight = (vote['weight'] as num?)?.toDouble() ?? 1.0;
      if (choice == top1) {
        runoffCounts[top1] = (runoffCounts[top1] ?? 0.0) + weight;
        totalRunoffWeightedVotes += weight;
      } else if (choice == top2) {
        runoffCounts[top2] = (runoffCounts[top2] ?? 0.0) + weight;
        totalRunoffWeightedVotes += weight;
      }
    }

    String runoffWinner;
    // In case of a tie in runoff, the candidate who was ahead in the first round (top1) wins.
    // If they had equal votes in the first round, top1 (arbitrarily the first in sorted list) wins.
    if ((runoffCounts[top1] ?? 0.0) >= (runoffCounts[top2] ?? 0.0)) {
      runoffWinner = top1;
    } else {
      runoffWinner = top2;
    }

    return {
      "round1Counts": counts, // Weighted counts from round 1
      "runoffCounts": runoffCounts, // Weighted counts for the runoff
      "winner": runoffWinner,
      "majorityAchieved": false, // Majority not achieved in round 1
      "runoffNeeded": true,
      "totalVotesRound1": totalWeightedVotes,
      "totalVotesRunoff": totalRunoffWeightedVotes,
      "round": 2
    };
  }

  /// Schulze Method: A Condorcet method that finds a winner through pairwise comparisons.
  ///
  /// This implementation follows the standard Schulze method algorithm:
  /// 1. Calculate the pairwise preferences between all candidates
  /// 2. Find the strongest paths between all pairs of candidates using Floyd-Warshall
  /// 3. Determine the ranking based on the strongest paths
  ///
  /// The method handles weighted votes and supports both ranked and rated ballots.
  /// For rated ballots, higher ratings are considered better.
  ///
  /// Returns a map containing:
  /// - 'pairwisePreferences': The raw pairwise preference counts
  /// - 'strongestPaths': The strongest paths between all pairs of candidates
  /// - 'ranking': The final ranking of candidates (best first)
  /// - 'winner': The winner of the election
  /// - 'totalVotes': Total number of votes cast
  static Map<String, dynamic> calculateSchulze(
      List<Map<String, dynamic>> votes) {
    if (votes.isEmpty) {
      return {
        'pairwisePreferences': {},
        'strongestPaths': {},
        'ranking': [],
        'winner': null,
        'totalVotes': 0,
        'message': 'No votes cast',
      };
    }

    // Get all unique options from votes
    Set<String> options = {};
    for (var vote in votes) {
      final choice = vote['choice'];
      if (choice is Map) {
        options.addAll(choice.keys.cast<String>());
      }
    }

    if (options.isEmpty) {
      return {
        'pairwisePreferences': {},
        'strongestPaths': {},
        'ranking': [],
        'winner': null,
        'totalVotes': votes.length,
        'message': 'No valid votes with candidate preferences',
      };
    }

    final List<String> candidates = options.toList();

    // Initialize pairwise preference matrix
    final Map<String, Map<String, double>> d = {};
    for (var c1 in candidates) {
      d[c1] = {};
      for (var c2 in candidates) {
        if (c1 != c2) {
          d[c1]![c2] = 0.0;
        }
      }
    }

    // Calculate pairwise preferences with vote weights
    for (var vote in votes) {
      final Map<String, dynamic>? rankings = vote['choice'] as Map<String, dynamic>?;
      final double weight = (vote['weight'] as num?)?.toDouble() ?? 1.0;
      
      if (rankings == null) continue;

        // For each pair of candidates, count preferences with weights
        final List<MapEntry<String, dynamic>> rankedCandidates = 
            rankings.entries.where((e) => candidates.contains(e.key)).toList();
            
        // Sort candidates by ranking (lower rank = better)
        rankedCandidates.sort((a, b) {
          final rankA = a.value is num ? (a.value as num).toDouble() : 0.0;
          final rankB = b.value is num ? (b.value as num).toDouble() : 0.0;
          return rankA.compareTo(rankB);
        });
        
        // For each pair where i is ranked higher than j, add weight to d[i][j]
        for (int i = 0; i < rankedCandidates.length; i++) {
          final c1 = rankedCandidates[i].key;
          for (int j = i + 1; j < rankedCandidates.length; j++) {
            final c2 = rankedCandidates[j].key;
            d[c1]![c2] = (d[c1]?[c2] ?? 0.0) + weight;
          }
        }
    }

    // Initialize strongest path matrix
    final Map<String, Map<String, double>> p = {};
    for (var c1 in candidates) {
      p[c1] = {};
      for (var c2 in candidates) {
        if (c1 != c2) {
          p[c1]![c2] = d[c1]?[c2] ?? 0.0;
        }
      }
    }

    // Floyd-Warshall algorithm to find strongest paths
    for (var k in candidates) {
      for (var i in candidates) {
        if (i == k) continue;
        for (var j in candidates) {
          if (j == i || j == k) continue;
          
          // The strength of the path i -> k -> j is the minimum of i->k and k->j
          final strengthIK = p[i]?[k] ?? 0.0;
          final strengthKJ = p[k]?[j] ?? 0.0;
          final strengthIJ = p[i]?[j] ?? 0.0;
          
          // The new strength is the minimum of the two path segments
          final newStrength = strengthIK < strengthKJ ? strengthIK : strengthKJ;
          
          // Update if this is a stronger path
          if (strengthIJ < newStrength) {
            p[i]![j] = newStrength;
          }
        }
      }
    }

    // Calculate the ranking using the Schulze method
    // A candidate A is ranked higher than B if the strongest path from A to B is stronger than from B to A
    final sortedCandidates = List<String>.from(candidates);
    sortedCandidates.sort((a, b) {
      final strengthAB = p[a]?[b] ?? 0.0;
      final strengthBA = p[b]?[a] ?? 0.0;
      
      // If A is preferred over B, sort A before B
      if (strengthAB > strengthBA) return -1;
      // If B is preferred over A, sort B before A
      if (strengthBA > strengthAB) return 1;
      // If they're tied, maintain original order (should be rare)
      return 0;
    });

    
    // The winner is the first in the sorted list
    final String? winner = sortedCandidates.isNotEmpty ? sortedCandidates[0] : null;

    // Prepare detailed results
    final Map<String, Map<String, dynamic>> pairwiseDetails = {};
    for (var c1 in candidates) {
      pairwiseDetails[c1] = {};
      for (var c2 in candidates) {
        if (c1 != c2) {
          pairwiseDetails[c1]![c2] = {
            'preference': d[c1]?[c2] ?? 0.0,
            'strongestPath': p[c1]?[c2] ?? 0.0,
          };
        }
      }
    }

    // Calculate total votes as the sum of all vote weights
    final double totalVotes = votes.fold<double>(0, (sum, vote) => sum + ((vote['weight'] as num?)?.toDouble() ?? 1.0));

    return {
      'pairwisePreferences': d,
      'strongestPaths': p,
      'ranking': sortedCandidates,
      'winner': winner,
      'totalVotes': totalVotes,
      'details': {
        'candidates': candidates,
        'pairwiseDetails': pairwiseDetails,
      },
    };
  }

  /// Instant Runoff Voting (IRV): Eliminate last place, transfer votes.
  ///
  /// Status: PROTOTYPE IMPLEMENTATION (Future Sprint)
  ///
  /// This is a prototype implementation of Instant Runoff Voting (IRV), where
  /// voters rank candidates in order of preference. The candidate with the fewest
  /// first-place votes is eliminated, and their votes are transferred to the next
  /// preferred candidate. This process continues until a candidate has a majority.
  ///
  /// TODO: Improve handling of tied rankings.
  /// TODO: Add comprehensive test coverage.
  /// TODO: Optimize for large elections.
  static Map<String, dynamic> calculateInstantRunoff(
      List<Map<String, dynamic>> votes) {
    // Get all unique options from rankings
    Set<String> options = {};
    for (var vote in votes) {
      final rankings = vote['choice'];
      if (rankings is Map) {
        options.addAll(rankings.keys.cast<String>());
      }
    }

    List<String> remainingOptions = options.toList();
    Map<String, int> firstPlaceVotes = {};
    Map<int, List<Map<String, dynamic>>> rounds = {};
    String? winner;
    int round = 1;

    while (winner == null && remainingOptions.length > 1) {
      // Reset first place votes count
      firstPlaceVotes = {};
      for (var option in remainingOptions) {
        firstPlaceVotes[option] = 0;
      }

      // Count first place votes for each option
      for (var vote in votes) {
        final Map<String, dynamic>? rankings =
            vote['choice'] as Map<String, dynamic>?;
        if (rankings != null) {
          // Find the highest ranked remaining option
          String? highestRanked;
          int highestRank = 999; // Large number

          for (var option in remainingOptions) {
            final rank = rankings[option] as int?;
            if (rank != null && rank > 0 && rank < highestRank) {
              highestRank = rank;
              highestRanked = option;
            }
          }

          if (highestRanked != null) {
            firstPlaceVotes[highestRanked] =
                (firstPlaceVotes[highestRanked] ?? 0) + 1;
          }
        }
      }

      // Store round results
      rounds[round] = [
        for (var entry in firstPlaceVotes.entries)
          {
            "option": entry.key,
            "votes": entry.value,
            "percentage": votes.isEmpty
                ? 0.0
                : "${(entry.value / votes.length * 100).toStringAsFixed(1)}%",
          }
      ];

      // Check for majority winner
      firstPlaceVotes.forEach((option, count) {
        if (count > votes.length / 2) {
          winner = option;
        }
      });

      // If no winner, eliminate last place
      if (winner == null && remainingOptions.length > 1) {
        String? lastPlace;
        int minVotes = votes.length + 1; // Larger than possible

        firstPlaceVotes.forEach((option, count) {
          if (count < minVotes) {
            minVotes = count;
            lastPlace = option;
          }
        });

        if (lastPlace != null) {
          remainingOptions.remove(lastPlace);
        }
      }

      // If we're down to the last option or a tie, declare winner
      if (winner == null && remainingOptions.length == 1) {
        winner = remainingOptions.first;
      }

      round++;
    }

    return {
      "rounds": rounds,
      "winner": winner,
      "totalVotes": votes.length,
    };
  }

  /// STAR Voting: Score Then Automatic Runoff.
  ///
  /// Status: PROTOTYPE IMPLEMENTATION (Future Sprint)
  ///
  /// This is a prototype implementation of STAR (Score Then Automatic Runoff) Voting,
  /// where voters score each candidate from 0-5. The two highest-scoring candidates
  /// advance to an automatic runoff, where the candidate preferred by more voters wins.
  ///
  /// TODO: Add validation for score ranges.
  /// TODO: Add comprehensive test coverage.
  /// TODO: Improve handling of edge cases (ties, etc.).
  static Map<String, dynamic> calculateStarVoting(
      List<Map<String, dynamic>> votes) {
    // Get all unique options
    Set<String> options = {};
    for (var vote in votes) {
      final ratings = vote['choice'];
      if (ratings is Map) {
        options.addAll(ratings.keys.cast<String>());
      }
    }

    // Calculate scores for each option
    Map<String, double> scores = {};
    for (var option in options) {
      scores[option] = 0.0;
    }

    for (var vote in votes) {
      final Map<String, dynamic>? ratings =
          vote['choice'] as Map<String, dynamic>?;
      if (ratings != null) {
        for (var option in options) {
          final rating = ratings[option] as double?;
          if (rating != null) {
            scores[option] = (scores[option] ?? 0.0) + rating;
          }
        }
      }
    }

    // Find top two candidates by score
    List<MapEntry<String, double>> sortedByScore = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    String? firstFinalist;
    String? secondFinalist;

    if (sortedByScore.isNotEmpty) {
      firstFinalist = sortedByScore[0].key;
    }
    if (sortedByScore.length >= 2) {
      secondFinalist = sortedByScore[1].key;
    }

    // If we don't have two finalists, return the available winner
    if (firstFinalist == null) {
      return {
        "scores": scores,
        "winner": null,
        "totalVotes": votes.length,
      };
    } else if (secondFinalist == null) {
      return {
        "scores": scores,
        "winner": firstFinalist,
        "totalVotes": votes.length,
      };
    }

    // Automatic runoff between top two
    int firstPreferred = 0;
    int secondPreferred = 0;

    for (var vote in votes) {
      final Map<String, dynamic>? ratings =
          vote['choice'] as Map<String, dynamic>?;
      if (ratings != null) {
        final firstRating = ratings[firstFinalist] as double? ?? 0.0;
        final secondRating = ratings[secondFinalist] as double? ?? 0.0;

        if (firstRating > secondRating) {
          firstPreferred++;
        } else if (secondRating > firstRating) {
          secondPreferred++;
        }
        // If tied ratings, no preference counted
      }
    }

    // Determine winner
    String winner =
        firstPreferred >= secondPreferred ? firstFinalist : secondFinalist;

    return {
      "scores": scores,
      "finalists": [firstFinalist, secondFinalist],
      "runoffResults": {
        firstFinalist: firstPreferred,
        secondFinalist: secondPreferred,
      },
      "winner": winner,
      "totalVotes": votes.length,
    };
  }

  /// Range Voting: Average rating for each option.
  ///
  /// Status: PROTOTYPE IMPLEMENTATION (Future Sprint)
  ///
  /// This is a prototype implementation of Range Voting, where voters rate each
  /// candidate on a scale, and the candidate with the highest average rating wins.
  ///
  /// TODO: Add validation for rating ranges.
  /// TODO: Add comprehensive test coverage.
  /// TODO: Consider normalization techniques to prevent strategic voting.
  static Map<String, dynamic> calculateRangeVoting(
      List<Map<String, dynamic>> votes) {
    // Get all unique options
    Set<String> options = {};
    for (var vote in votes) {
      final ratings = vote['choice'];
      if (ratings is Map) {
        options.addAll(ratings.keys.cast<String>());
      }
    }

    // Calculate ratings for each option
    Map<String, List<double>> allRatings = {};
    for (var option in options) {
      allRatings[option] = [];
    }

    for (var vote in votes) {
      final Map<String, dynamic>? ratings =
          vote['choice'] as Map<String, dynamic>?;
      if (ratings != null) {
        for (var option in options) {
          final rating = ratings[option] as double?;
          if (rating != null) {
            allRatings[option]!.add(rating);
          }
        }
      }
    }

    // Calculate average ratings
    Map<String, double> averageRatings = {};
    for (var option in options) {
      final ratings = allRatings[option] ?? [];
      if (ratings.isNotEmpty) {
        final sum = ratings.reduce((a, b) => a + b);
        averageRatings[option] = sum / ratings.length;
      } else {
        averageRatings[option] = 0.0;
      }
    }

    // Find the option with the highest average rating
    String? winner;
    double maxRating = -1.0;

    averageRatings.forEach((option, rating) {
      if (rating > maxRating) {
        maxRating = rating;
        winner = option;
      }
    });

    return {
      "averageRatings": averageRatings,
      "winner": winner,
      "totalVotes": votes.length,
    };
  }

  /// Majority Judgment: Median judgment for each option.
  ///
  /// Status: PROTOTYPE IMPLEMENTATION (Future Sprint)
  ///
  /// This is a prototype implementation of Majority Judgment, where voters grade
  /// candidates on a qualitative scale (Excellent, Very Good, Good, etc.), and
  /// the candidate with the highest median grade wins.
  ///
  /// TODO: Implement tie-breaking through removing median grades.
  /// TODO: Add comprehensive test coverage.
  /// TODO: Refine judgment scale and validation.
  static Map<String, dynamic> calculateMajorityJudgment(
      List<Map<String, dynamic>> votes) {
    // Get all unique options and judgments
    Set<String> options = {};
    for (var vote in votes) {
      final judgments = vote['choice'];
      if (judgments is Map) {
        options.addAll(judgments.keys.cast<String>());
      }
    }

    // Define judgment values from highest to lowest
    final List<String> judgmentScale = [
      'Excellent',
      'Very Good',
      'Good',
      'Acceptable',
      'Poor',
      'Reject'
    ];

    // Collect all judgments for each option
    Map<String, List<String>> allJudgments = {};
    for (var option in options) {
      allJudgments[option] = [];
    }

    for (var vote in votes) {
      final Map<String, dynamic>? judgments =
          vote['choice'] as Map<String, dynamic>?;
      if (judgments != null) {
        for (var option in options) {
          final judgment = judgments[option] as String?;
          if (judgment != null) {
            allJudgments[option]!.add(judgment);
          }
        }
      }
    }

    // Find median judgment for each option
    Map<String, String> medianJudgments = {};
    for (var option in options) {
      final judgments = allJudgments[option] ?? [];
      if (judgments.isNotEmpty) {
        // Sort judgments by their position in the scale (best first)
        judgments.sort((a, b) {
          final aIndex = judgmentScale.indexOf(a);
          final bIndex = judgmentScale.indexOf(b);
          return aIndex.compareTo(bIndex); // Lower index = better judgment
        });

        // Find median judgment
        final medianIndex = judgments.length ~/ 2;
        medianJudgments[option] = judgments[medianIndex];
      } else {
        medianJudgments[option] =
            judgmentScale.last; // Default to worst judgment
      }
    }

    // Find the option with the best median judgment
    String? winner;
    int bestJudgmentIndex = judgmentScale.length; // Start with worst possible

    medianJudgments.forEach((option, judgment) {
      final judgmentIndex = judgmentScale.indexOf(judgment);
      if (judgmentIndex < bestJudgmentIndex) {
        bestJudgmentIndex = judgmentIndex;
        winner = option;
      }
    });

    return {
      "medianJudgments": medianJudgments,
      "winner": winner,
      "judgmentScale": judgmentScale,
      "totalVotes": votes.length,
    };
  }

  /// Quadratic Voting: Each vote costs votes² credits.
  ///
  /// Status: PROTOTYPE IMPLEMENTATION (Future Sprint)
  ///
  /// This is a prototype implementation of Quadratic Voting, where voters allocate
  /// credits to different options, with the cost of votes increasing quadratically.
  /// This allows voters to express intensity of preferences.
  ///
  /// TODO: Add proper credit validation and allocation.
  /// TODO: Add comprehensive test coverage.
  /// TODO: Implement mechanisms to prevent strategic voting.
  static Map<String, dynamic> calculateQuadraticVoting(
      List<Map<String, dynamic>> votes) {
    // Get all unique options
    Set<String> options = {};
    for (var vote in votes) {
      final optionVotes = vote['choice'];
      if (optionVotes is Map) {
        options.addAll(optionVotes.keys.cast<String>());
      }
    }

    // Count total votes for each option
    Map<String, int> totalVotes = {};
    for (var option in options) {
      totalVotes[option] = 0;
    }

    for (var vote in votes) {
      final Map<String, dynamic>? optionVotes =
          vote['choice'] as Map<String, dynamic>?;
      if (optionVotes != null) {
        for (var option in options) {
          final voteCount = optionVotes[option] as int?;
          if (voteCount != null) {
            totalVotes[option] = (totalVotes[option] ?? 0) + voteCount;
          }
        }
      }
    }

    // Find the option with the most votes
    String? winner;
    int maxVotes = -1;

    totalVotes.forEach((option, count) {
      if (count > maxVotes) {
        maxVotes = count;
        winner = option;
      }
    });

    return {
      "totalVotes": totalVotes,
      "winner": winner,
      "voterCount": votes.length,
    };
  }

  /// Condorcet Method: Pairwise comparisons between all options.
  ///
  /// Status: PROTOTYPE IMPLEMENTATION (Future Sprint)
  ///
  /// This is a prototype implementation of the Condorcet Method, which determines
  /// a winner by conducting pairwise comparisons between all candidates. The
  /// Condorcet winner is the candidate who would win a two-candidate election
  /// against each of the other candidates.
  ///
  /// TODO: Implement proper cycle resolution (Condorcet paradox).
  /// TODO: Add comprehensive test coverage.
  /// TODO: Optimize for large numbers of candidates.
  static Map<String, dynamic> calculateCondorcet(
      List<Map<String, dynamic>> votes) {
    // Get all unique options
    Set<String> options = {};
    for (var vote in votes) {
      final rankings = vote['choice'];
      if (rankings is Map) {
        options.addAll(rankings.keys.cast<String>());
      }
    }

    // Create pairwise comparison matrix
    Map<String, Map<String, int>> pairwiseWins = {};
    for (var option1 in options) {
      pairwiseWins[option1] = {};
      for (var option2 in options) {
        if (option1 != option2) {
          pairwiseWins[option1]![option2] = 0;
        }
      }
    }

    // Calculate pairwise wins
    for (var vote in votes) {
      final Map<String, dynamic>? rankings =
          vote['choice'] as Map<String, dynamic>?;
      if (rankings != null) {
        for (var option1 in options) {
          for (var option2 in options) {
            if (option1 != option2) {
              final rank1 = rankings[option1] as int?;
              final rank2 = rankings[option2] as int?;
              if (rank1 != null && rank2 != null && rank1 < rank2) {
                pairwiseWins[option1]![option2] =
                    (pairwiseWins[option1]![option2] ?? 0) + 1;
              }
            }
          }
        }
      }
    }

    // Find Condorcet winner (if any)
    String? winner;
    for (var candidate in options) {
      bool winsAllPairwise = true;
      for (var opponent in options) {
        if (candidate != opponent) {
          final candidateWins = pairwiseWins[candidate]![opponent] ?? 0;
          final opponentWins = pairwiseWins[opponent]![candidate] ?? 0;
          if (candidateWins <= opponentWins) {
            winsAllPairwise = false;
            break;
          }
        }
      }
      if (winsAllPairwise) {
        winner = candidate;
        break;
      }
    }

    return {
      "pairwiseWins": pairwiseWins,
      "winner": winner, // Will be null if no Condorcet winner exists
      "totalVotes": votes.length,
    };
  }

  /// Borda Count: Points assigned based on ranking.
  ///
  /// Status: PROTOTYPE IMPLEMENTATION (Future Sprint)
  ///
  /// This is a prototype implementation of the Borda Count method, where voters
  /// rank candidates and points are assigned based on those rankings (e.g., n-1 points
  /// for first place, n-2 for second, etc.). The candidate with the most points wins.
  ///
  /// TODO: Add validation for ranking completeness.
  /// TODO: Add comprehensive test coverage.
  /// TODO: Consider different point allocation schemes.
  static Map<String, dynamic> calculateBordaCount(
      List<Map<String, dynamic>> votes) {
    // Get all unique options
    Set<String> options = {};
    for (var vote in votes) {
      final rankings = vote['choice'];
      if (rankings is Map) {
        options.addAll(rankings.keys.cast<String>());
      }
    }

    Map<String, int> points = {};
    for (var option in options) {
      points[option] = 0;
    }

    // Calculate Borda points
    for (var vote in votes) {
      final Map<String, dynamic>? rankings =
          vote['choice'] as Map<String, dynamic>?;
      if (rankings != null) {
        for (var option in options) {
          final rank = rankings[option] as int?;
          if (rank != null && rank > 0) {
            // In Borda count, points are assigned in reverse:
            // If there are n candidates, 1st place gets n-1 points, 2nd gets n-2, etc.
            points[option] = (points[option] ?? 0) + (options.length - rank);
          }
        }
      }
    }

    // Find the option with the most points
    String? winner;
    int maxPoints = -1;

    points.forEach((option, score) {
      if (score > maxPoints) {
        maxPoints = score;
        winner = option;
      }
    });

    return {
      "points": points,
      "winner": winner,
      "totalVotes": votes.length,
    };
  }

  /// Cumulative Voting: Distribute fixed number of votes across options.
  ///
  /// Status: PROTOTYPE IMPLEMENTATION (Future Sprint)
  ///
  /// This is a prototype implementation of Cumulative Voting, where voters have
  /// a fixed number of votes that they can distribute among candidates as they choose,
  /// allowing them to express intensity of preferences.
  ///
  /// TODO: Add validation for vote allocation (ensure total doesn't exceed limit).
  /// TODO: Add comprehensive test coverage.
  /// TODO: Consider different allocation strategies.
  static Map<String, dynamic> calculateCumulativeVoting(
      List<Map<String, dynamic>> votes) {
    // Get all unique options
    Set<String> options = {};
    for (var vote in votes) {
      final voteCounts = vote['choice'];
      if (voteCounts is Map) {
        options.addAll(voteCounts.keys.cast<String>());
      }
    }

    // Count total votes for each option
    Map<String, int> totalVotes = {};
    for (var option in options) {
      totalVotes[option] = 0;
    }

    for (var vote in votes) {
      final Map<String, dynamic>? voteCounts =
          vote['choice'] as Map<String, dynamic>?;
      if (voteCounts != null) {
        for (var option in options) {
          final voteCount = voteCounts[option] as int?;
          if (voteCount != null) {
            totalVotes[option] = (totalVotes[option] ?? 0) + voteCount;
          }
        }
      }
    }

    // Find the option with the most votes
    String? winner;
    int maxVotes = -1;

    totalVotes.forEach((option, count) {
      if (count > maxVotes) {
        maxVotes = count;
        winner = option;
      }
    });

    return {
      "totalVotes": totalVotes,
      "winner": winner,
      "voterCount": votes.length,
    };
  }

  /// Kemeny-Young Method: Find ranking with minimum pairwise disagreements.
  ///
  /// Status: PROTOTYPE IMPLEMENTATION (Future Sprint)
  ///
  /// This is a prototype implementation of the Kemeny-Young Method, which finds the
  /// ranking of candidates that minimizes the number of pairwise disagreements with
  /// voters' preferences. This is an NP-hard problem, so this implementation uses
  /// a simplified approach.
  ///
  /// TODO: Implement a more efficient algorithm (current is O(n!) complexity).
  /// TODO: Add comprehensive test coverage.
  /// TODO: Consider approximation algorithms for large numbers of candidates.
  static Map<String, dynamic> calculateKemenyYoung(
      List<Map<String, dynamic>> votes) {
    // Note: Full Kemeny-Young implementation is complex
    // This is a simplified version that uses a heuristic approach
    // Get all unique options
    Set<String> options = {};
    for (var vote in votes) {
      final rankings = vote['choice'];
      if (rankings is Map) {
        options.addAll(rankings.keys.cast<String>());
      }
    }

    // Create pairwise preference matrix
    Map<String, Map<String, int>> preferences = {};
    for (var option1 in options) {
      preferences[option1] = {};
      for (var option2 in options) {
        if (option1 != option2) {
          preferences[option1]![option2] = 0;
        }
      }
    }

    // Calculate pairwise preferences
    for (var vote in votes) {
      final Map<String, dynamic>? rankings =
          vote['choice'] as Map<String, dynamic>?;
      if (rankings != null) {
        for (var option1 in options) {
          for (var option2 in options) {
            if (option1 != option2) {
              final rank1 = rankings[option1] as int?;
              final rank2 = rankings[option2] as int?;
              if (rank1 != null && rank2 != null && rank1 < rank2) {
                preferences[option1]![option2] =
                    (preferences[option1]![option2] ?? 0) + 1;
              }
            }
          }
        }
      }
    }

    // For a simplified approach, we'll use a Borda-like count
    Map<String, int> scores = {};
    for (var option in options) {
      scores[option] = 0;
      for (var otherOption in options) {
        if (option != otherOption) {
          scores[option] =
              (scores[option] ?? 0) + (preferences[option]![otherOption] ?? 0);
        }
      }
    }

    // Find the option with the highest score
    String? winner;
    int maxScore = -1;

    scores.forEach((option, score) {
      if (score > maxScore) {
        maxScore = score;
        winner = option;
      }
    });

    return {
      "preferences": preferences,
      "scores": scores,
      "winner": winner,
      "totalVotes": votes.length,
    };
  }

  /// Dual Choice: Simple yes/no voting.
  ///
  /// Status: PROTOTYPE IMPLEMENTATION (Future Sprint)
  ///
  /// This is a prototype implementation of Dual Choice voting, which is a simple
  /// binary choice voting system (yes/no, approve/reject, etc.).
  ///
  /// TODO: Add validation for binary choices.
  /// TODO: Add comprehensive test coverage.
  /// TODO: Consider adding support for abstentions.
  static Map<String, dynamic> calculateDualChoice(
      List<Map<String, dynamic>> votes) {
    // For this implementation, dual choice is similar to First Past the Post
    return calculateFirstPastThePost(votes);
  }

  /// Weight Voting: Votes weighted by user's stake or importance.
  ///
  /// Status: PROTOTYPE IMPLEMENTATION (Future Sprint)
  ///
  /// This is a prototype implementation of Weight Voting, where votes are weighted
  /// based on some measure of the voter's stake or importance. This will be
  /// particularly relevant for Sprint 3 (Liquid Democracy).
  ///
  /// TODO: Implement proper weight verification and validation.
  /// TODO: Add comprehensive test coverage.
  /// TODO: Integrate with delegation system in Sprint 3.
  static Map<String, dynamic> calculateWeightVoting(
      List<Map<String, dynamic>> votes) {
    final logger = Logger(); // Keep logger if used
    Map<String, double> counts = {};
    double totalWeightedSum = 0.0;

    if (votes.isEmpty) {
      logger.i("No votes provided for Weight Voting.");
      return {
        "counts": counts,
        "winner": null,
        "totalWeight": 0.0, // Changed key
        "distinctVoters": 0,
        "message": "No weighted votes cast for Weight Voting."
      };
    }

    // Count weighted votes for each option
    for (var vote in votes) {
      final choice = vote['choice'];
      final weight = (vote['weight'] as num?)?.toDouble() ?? 1.0;

      if (choice != null && choice is String) {
        counts[choice] = (counts[choice] ?? 0.0) + weight;
        totalWeightedSum += weight; // Sum of all weights processed
      } else if (choice != null && choice is List) {
        // If choice is a list, apply weight to each selected option (like Approval)
        // This makes WeightVoting more versatile if the proposal allows multiple selections.
        bool voteWeightAddedToSum = false;
        for (var subChoice in choice) {
          if (subChoice is String) {
            counts[subChoice] = (counts[subChoice] ?? 0.0) + weight;
            if (!voteWeightAddedToSum) {
              totalWeightedSum +=
                  weight; // Add vote's weight to sum once if any valid subChoice
              voteWeightAddedToSum = true;
            }
          }
        }
      } else {
        logger.w(
            "Skipping vote with unhandled choice type: ${choice.runtimeType}");
      }
    }

    if (counts.isEmpty) {
      logger.i("No valid choices found in votes for Weight Voting.");
      return {
        "counts": counts,
        "winner": null,
        "totalWeight": totalWeightedSum, // Changed key
        "distinctVoters": votes.length,
        "message": "No valid choices found in votes for Weight Voting."
      };
    }

    // Find winner
    String? winner;
    double maxWeightedVotes =
        -1.0; // Initialize to handle all non-negative counts

    counts.forEach((option, count) {
      if (count > maxWeightedVotes) {
        maxWeightedVotes = count;
        winner = option;
      }
    });

    return {
      "counts": counts,
      "winner": winner,
      "totalWeight": totalWeightedSum, // Changed key
      "distinctVoters": votes.length,
    };
  }
}
