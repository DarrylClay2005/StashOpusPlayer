package com.stash.opusplayer.folder.ui.adapters

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.fragment.app.FragmentActivity
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import kotlinx.coroutines.withContext
import kotlinx.coroutines.launch
import androidx.lifecycle.findViewTreeLifecycleOwner
import androidx.lifecycle.lifecycleScope

data class FolderItem(
    val path: String,
    val displayName: String,
    val songCount: Int,
    val artworkPath: String? = null
)

class RevolutionaryFolderAdapter(private val items: List<FolderItem>) : RecyclerView.Adapter<RevolutionaryFolderAdapter.ViewHolder>() {

    class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val title: TextView = view.findViewById(com.stash.opusplayer.R.id.folder_title)
        val subtitle: TextView = view.findViewById(com.stash.opusplayer.R.id.folder_subtitle)
        val artwork: ImageView = view.findViewById(com.stash.opusplayer.R.id.folder_artwork)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val v = LayoutInflater.from(parent.context).inflate(com.stash.opusplayer.R.layout.item_folder, parent, false)
        return ViewHolder(v)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val item = items[position]
        // Truncate long folder names (ellipsis) — TextView in layout handles ellipsize
        holder.title.text = item.displayName
        holder.subtitle.text = "${item.songCount} song${if (item.songCount == 1) "" else "s"} — ${item.path}"

        // Load artwork if provided, otherwise load folder icon
        if (!item.artworkPath.isNullOrBlank()) {
            Glide.with(holder.artwork.context)
                .load(item.artworkPath)
                .centerCrop()
                .into(holder.artwork)
        } else {
            Glide.with(holder.artwork.context)
                .load(com.stash.opusplayer.R.drawable.ic_folder)
                .into(holder.artwork)
        }

        holder.itemView.setOnClickListener {
            val ctx = holder.itemView.context
            try {
                val repo = com.stash.opusplayer.data.MusicRepository(ctx)
                holder.itemView.findViewTreeLifecycleOwner()?.lifecycleScope?.launch(kotlinx.coroutines.Dispatchers.Main) {
                    val songs = withContext(kotlinx.coroutines.Dispatchers.IO) { repo.getSongsInFolder(item.path) }
                    val fragment = com.stash.opusplayer.ui.fragments.FolderSongsFragment.newInstance(
                        item.displayName,
                        ArrayList(songs)
                    )
                    if (ctx is FragmentActivity) {
                        ctx.supportFragmentManager.beginTransaction()
                            .replace(com.stash.opusplayer.R.id.main_content, fragment)
                            .addToBackStack(null)
                            .commit()
                    }
                }
            } catch (e: Exception) {
                // ignore navigation errors
            }
        }
    }

    override fun getItemCount(): Int = items.size
}
