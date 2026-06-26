import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import 'package:google_fonts/google_fonts.dart';

class MemberLicencesScreen extends StatelessWidget {
  const MemberLicencesScreen({super.key});

  final List<Map<String, String>> _packages = const [
    {
      'name': 'flutter',
      'licenseType': 'BSD 3-Clause License',
      'description': 'Flutter SDK for building multi-platform applications.',
      'text': 'Copyright 2014 The Flutter Authors. All rights reserved.\n\n'
          'Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:\n\n'
          '1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.\n'
          '2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.\n'
          '3. Neither the name of Google Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.\n\n'
          'THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.'
    },
    {
      'name': 'supabase_flutter',
      'licenseType': 'MIT License',
      'description': 'Flutter client for Supabase database, auth, and storage services.',
      'text': 'Copyright (c) 2021 Supabase Community\n\n'
          'Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:\n\n'
          'The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.\n\n'
          'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.'
    },
    {
      'name': 'google_fonts',
      'licenseType': 'Apache License 2.0',
      'description': 'A Flutter package to use fonts from fonts.google.com dynamically.',
      'text': 'Copyright 2020 Google LLC\n\n'
          'Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.\n'
          'You may obtain a copy of the License at\n\n'
          'http://www.apache.org/licenses/LICENSE-2.0\n\n'
          'Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.'
    },
    {
      'name': 'image_picker',
      'licenseType': 'BSD 3-Clause License',
      'description': 'Flutter plugin for selecting images from the Android and iOS image library, and taking new pictures.',
      'text': 'Copyright 2013 The Flutter Authors. All rights reserved.\n\n'
          'Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:\n\n'
          '1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.\n'
          '2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.\n'
          '3. Neither the name of Google Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.'
    },
    {
      'name': 'image_cropper',
      'licenseType': 'MIT License',
      'description': 'A Flutter plugin for cropping images on Android, iOS, and Web.',
      'text': 'Copyright (c) 2019 Hung Nguyen-Minh\n\n'
          'Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:\n\n'
          'The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.'
    },
    {
      'name': 'shared_preferences',
      'licenseType': 'BSD 3-Clause License',
      'description': 'Flutter plugin for reading and writing simple key-value pairs.',
      'text': 'Copyright 2013 The Flutter Authors. All rights reserved.\n\n'
          'Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:\n\n'
          '1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.\n'
          '2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.'
    },
    {
      'name': 'share_plus',
      'licenseType': 'BSD 3-Clause License',
      'description': 'Flutter plugin for sharing content via the platform share sheet.',
      'text': 'Copyright 2017 The Chromium Authors. All rights reserved.\n\n'
          'Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:\n\n'
          '1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.\n'
          '2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.'
    },
    {
      'name': 'url_launcher',
      'licenseType': 'BSD 3-Clause License',
      'description': 'Flutter plugin for launching a URL in the mobile browser or email client.',
      'text': 'Copyright 2013 The Flutter Authors. All rights reserved.\n\n'
          'Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:\n\n'
          '1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.\n'
          '2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.'
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE65C00),
      body: SafeArea(
        top: true,
        child: Scaffold(
          backgroundColor: context.palette.scaffold,
          appBar: AppBar(
            backgroundColor: const Color(0xFFE65C00),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'Open Source Licences',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            centerTitle: true,
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Text(
                  'The SILENCE app is built using these awesome open-source packages. Click on any package to view its license.',
                  style: GoogleFonts.inter(fontSize: 12.5, color: Colors.grey[600], height: 1.4),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: _packages.length,
                  itemBuilder: (context, index) {
                    final pkg = _packages[index];
                    return Card(
                      color: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          iconColor: const Color(0xFFE65C00),
                          collapsedIconColor: Colors.grey,
                          title: Text(
                            pkg['name']!,
                            style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 2),
                              Text(
                                pkg['licenseType']!,
                                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                pkg['description']!,
                                style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey[500]),
                              ),
                            ],
                          ),
                          childrenPadding: const EdgeInsets.all(16),
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFBF5EE),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                pkg['text']!,
                                style: GoogleFonts.spaceMono(fontSize: 10, color: context.palette.textSecondary, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

