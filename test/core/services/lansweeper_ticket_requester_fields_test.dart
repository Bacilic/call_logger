import 'package:call_logger/core/services/lansweeper_ticket_requester_fields.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lansweeperAgentAsMatchingRequesterFields', () {
    test('domain username maps to Username and AgentUsername', () {
      expect(
        lansweeperAgentAsMatchingRequesterFields(r'gnk\v.drosos'),
        <String, String>{
          'Username': r'gnk\v.drosos',
          'AgentUsername': r'gnk\v.drosos',
        },
      );
    });

    test('email maps to Email and AgentEmail', () {
      expect(
        lansweeperAgentAsMatchingRequesterFields('v.drosos@hospkorinthos.gr'),
        <String, String>{
          'Email': 'v.drosos@hospkorinthos.gr',
          'AgentEmail': 'v.drosos@hospkorinthos.gr',
        },
      );
    });

    test('trims surrounding whitespace', () {
      expect(
        lansweeperAgentAsMatchingRequesterFields('  gnk\\v.drosos  '),
        <String, String>{
          'Username': r'gnk\v.drosos',
          'AgentUsername': r'gnk\v.drosos',
        },
      );
    });
  });
}
