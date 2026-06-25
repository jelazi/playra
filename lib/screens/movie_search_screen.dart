import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/movie_search/movie_search_cubit.dart';
import '../models/cinemeta_meta.dart';
import '../services/cinemeta_service.dart';
import 'widgets/stream_selection_sheet.dart';

/// Search movies (Cinemeta) and pick a Torrentio source to stream or download.
class MovieSearchScreen extends StatelessWidget {
  const MovieSearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => MovieSearchCubit(context.read<CinemetaService>()),
      child: const _MovieSearchView(),
    );
  }
}

class _MovieSearchView extends StatefulWidget {
  const _MovieSearchView();

  @override
  State<_MovieSearchView> createState() => _MovieSearchViewState();
}

class _MovieSearchViewState extends State<_MovieSearchView> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    context.read<MovieSearchCubit>().search(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('movies.search_title'.tr()),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: 'movies.search_hint'.tr(),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _submit),
              ),
            ),
          ),
          Expanded(
            child: BlocBuilder<MovieSearchCubit, MovieSearchState>(
              builder: (context, state) {
                switch (state.status) {
                  case MovieSearchStatus.idle:
                    return _hint(Icons.movie_filter_outlined, 'movies.search_prompt'.tr());
                  case MovieSearchStatus.loading:
                    return const Center(child: CircularProgressIndicator());
                  case MovieSearchStatus.empty:
                    return _hint(Icons.search_off, 'movies.no_results'.tr());
                  case MovieSearchStatus.error:
                    return _hint(Icons.error_outline, 'movies.search_error'.tr(args: [state.error ?? '']));
                  case MovieSearchStatus.results:
                    return _ResultsGrid(results: state.results);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _hint(IconData icon, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.grey),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class _ResultsGrid extends StatelessWidget {
  const _ResultsGrid({required this.results});

  final List<CinemetaMeta> results;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final columns = (width / 160).floor().clamp(2, 8);
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        childAspectRatio: 0.62,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: results.length,
      itemBuilder: (context, index) => _MovieCard(meta: results[index]),
    );
  }
}

class _MovieCard extends StatelessWidget {
  const _MovieCard({required this.meta});

  final CinemetaMeta meta;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => showStreamSelectionSheet(context, meta),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: meta.poster != null
                  ? Image.network(
                      meta.poster!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, _, _) => _placeholder(),
                    )
                  : _placeholder(),
            ),
          ),
          const SizedBox(height: 6),
          Text(meta.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
          if (meta.year != null) Text(meta.year!, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: Colors.grey.shade800,
      alignment: Alignment.center,
      child: const Icon(Icons.movie, size: 40, color: Colors.white54),
    );
  }
}
