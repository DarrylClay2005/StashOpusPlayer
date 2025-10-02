package com.stash.stashwave.ui.adapters

import android.text.Spanned
import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.core.text.HtmlCompat
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.stash.stashwave.R
import com.stash.stashwave.data.YouTubeComment
import com.stash.stashwave.databinding.ItemYoutubeCommentBinding

class YouTubeCommentsAdapter(
    private val onViewReplies: (YouTubeComment) -> Unit = {}
) : RecyclerView.Adapter<YouTubeCommentsAdapter.CommentVH>() {

    private val items = mutableListOf<YouTubeComment>()

    fun submitList(list: List<YouTubeComment>) {
        items.clear()
        items.addAll(list)
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): CommentVH {
        val binding = ItemYoutubeCommentBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return CommentVH(binding)
    }

    override fun getItemCount(): Int = items.size

    override fun onBindViewHolder(holder: CommentVH, position: Int) {
        holder.bind(items[position])
    }

    inner class CommentVH(private val binding: ItemYoutubeCommentBinding) : RecyclerView.ViewHolder(binding.root) {
        fun bind(item: YouTubeComment) {
            // Indent replies
            val isReply = item.parentId != null
            val density = binding.root.resources.displayMetrics.density
            val startPad = if (isReply) (32 * density).toInt() else 0
            binding.root.setPaddingRelative(startPad, binding.root.paddingTop, binding.root.paddingEnd, binding.root.paddingBottom)
            binding.authorName.text = item.authorName
            val spanned: Spanned = HtmlCompat.fromHtml(item.textHtml, HtmlCompat.FROM_HTML_MODE_LEGACY)
            binding.commentText.text = spanned
            binding.commentMeta.text = buildMeta(item)

            if (item.replyCount > 0 && item.commentId != null) {
                binding.viewRepliesButton.visibility = android.view.View.VISIBLE
                binding.viewRepliesButton.text = "View replies (${item.replyCount})"
                binding.viewRepliesButton.setOnClickListener { onViewReplies(item) }
            } else {
                binding.viewRepliesButton.visibility = android.view.View.GONE
                binding.viewRepliesButton.setOnClickListener(null)
            }

            if (!item.authorProfileImageUrl.isNullOrBlank()) {
                Glide.with(binding.authorAvatar.context)
                    .load(item.authorProfileImageUrl)
                    .placeholder(R.drawable.ic_person)
                    .error(R.drawable.ic_person)
                    .circleCrop()
                    .into(binding.authorAvatar)
            } else {
                binding.authorAvatar.setImageResource(R.drawable.ic_person)
            }
        }

        private fun buildMeta(item: YouTubeComment): String {
            val likes = if (item.likeCount > 0) " • ${item.likeCount} likes" else ""
            return item.publishedAt + likes
        }
    }
}
